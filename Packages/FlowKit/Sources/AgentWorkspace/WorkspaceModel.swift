import SwiftTerm
import SwiftUI

/// One agent session: a live PTY terminal running an agent CLI in a worktree.
@MainActor
final class AgentSession: Identifiable {
    let id = UUID()
    let kind: AgentKind?
    let terminal: LocalProcessTerminalView

    /// `kind == nil` → a plain interactive shell (no agent), launched in the worktree.
    /// `resume` → relaunch the agent continuing its last conversation in this directory.
    init(kind: AgentKind?, directory: String, prompt: String? = nil, resume: Bool = false) {
        self.kind = kind
        let command = resume ? (kind?.continueCommand ?? kind?.launch(prompt: prompt)) : kind?.launch(prompt: prompt)
        self.terminal = makeTerminal(directory: directory, command: command)
    }

    var title: String { kind?.title ?? "Terminal" }

    func terminate() { terminal.terminate() }

    /// Type a prompt into the live agent and submit it. The Enter is sent as a separate
    /// event after a short delay — Ink-based TUIs (Claude Code) drop a `\r` that arrives
    /// in the same buffer as a large pasted block.
    func sendPrompt(_ text: String) {
        terminal.send(txt: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak terminal] in
            terminal?.send(txt: "\r")
        }
    }

    /// Best-effort scrape of the visible terminal screen (raw rendered text).
    func snapshot(maxLines: Int) -> String {
        let t = terminal.getTerminal()
        let rows = t.rows, cols = t.cols
        guard rows > 0, cols > 0 else { return "" }
        let startRow = max(0, rows - maxLines)
        return t.getText(start: Position(col: 0, row: startRow),
                         end: Position(col: cols - 1, row: rows - 1))
    }
}

/// A workspace = a git worktree on its own branch. Agent sessions run inside it,
/// isolated from the main checkout and from other workspaces.
@MainActor
@Observable
final class Workspace: Identifiable {
    let id = UUID()
    let repoPath: String
    let branch: String
    let worktreePath: String
    var sessions: [AgentSession] = []
    var selectedSessionID: AgentSession.ID?
    var diff: DiffStat = .zero
    var changes: [FileChange] = []
    var selectedFile: String?
    var fileDiff: String = ""
    var fullDiff: String = ""
    var ports: [Int] = []
    var ahead = 0
    var behind = 0
    var creatingPR = false
    var currentBranch: String
    var branches: [String] = []

    /// True when this workspace points at the repo's main checkout (current branch),
    /// not an isolated worktree.
    var isMainCheckout: Bool { worktreePath == repoPath }

    init(repoPath: String, branch: String, worktreePath: String) {
        self.repoPath = repoPath
        self.branch = branch
        self.worktreePath = worktreePath
        self.currentBranch = branch
    }

    func switchBranch(_ name: String) {
        guard name != currentBranch else { return }
        let path = worktreePath
        Task.detached {
            try? GitWorktrees.checkout(path, branch: name)
            let cur = GitWorktrees.currentBranch(path)
            await MainActor.run { self.currentBranch = cur; self.refreshDiff() }
        }
    }

    var repoName: String { (repoPath as NSString).lastPathComponent }

    func openSession(_ kind: AgentKind, prompt: String? = nil) {
        MCPConfig.wireWorktree(worktreePath)   // ensure .mcp.json exists before launch
        let session = AgentSession(kind: kind, directory: worktreePath, prompt: prompt)
        sessions.append(session)
        selectedSessionID = session.id
    }

    /// Open a plain interactive terminal in the worktree — no agent.
    func openTerminal() {
        let session = AgentSession(kind: nil, directory: worktreePath)
        sessions.append(session)
        selectedSessionID = session.id
    }

    /// Resume an agent's last conversation in this worktree (claude --continue).
    func resumeSession(_ kind: AgentKind) {
        MCPConfig.wireWorktree(worktreePath)
        let session = AgentSession(kind: kind, directory: worktreePath, resume: true)
        sessions.append(session)
        selectedSessionID = session.id
    }

    func closeSession(_ id: AgentSession.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].terminate()
        sessions.remove(at: idx)
        if selectedSessionID == id { selectedSessionID = sessions.last?.id }
    }

    func refreshDiff() {
        let path = worktreePath
        Task.detached {
            let files = GitWorktrees.changedFiles(path)
            let stat = DiffStat(files: files.count,
                                insertions: files.reduce(0) { $0 + $1.insertions },
                                deletions: files.reduce(0) { $0 + $1.deletions })
            let ports = GitWorktrees.listeningPorts(path)
            let ab = GitWorktrees.aheadBehind(path)
            let cur = GitWorktrees.currentBranch(path)
            let brs = GitWorktrees.localBranches(path)
            await MainActor.run {
                self.diff = stat
                self.changes = files
                self.ports = ports
                self.ahead = ab?.ahead ?? 0
                self.behind = ab?.behind ?? 0
                self.currentBranch = cur
                self.branches = brs
                if let sel = self.selectedFile, !files.contains(where: { $0.path == sel }) {
                    self.selectedFile = nil
                    self.fileDiff = ""
                }
            }
        }
    }

    /// Awaitable refresh — recomputes changes + full diff and returns only once set,
    /// so an MCP read isn't stale (unlike fire-and-forget refreshDiff).
    func refreshDiffAndWait() async {
        let path = worktreePath
        let files = await Task.detached { GitWorktrees.changedFiles(path) }.value
        let full = await Task.detached { GitWorktrees.fullDiff(path) }.value
        diff = DiffStat(files: files.count,
                        insertions: files.reduce(0) { $0 + $1.insertions },
                        deletions: files.reduce(0) { $0 + $1.deletions })
        changes = files
        fullDiff = full
    }

    func loadFullDiff() {
        let path = worktreePath
        Task.detached {
            let diff = GitWorktrees.fullDiff(path)
            await MainActor.run { self.fullDiff = diff }
        }
    }

    func selectFile(_ file: FileChange) {
        selectedFile = file.path
        let path = worktreePath
        Task.detached {
            let diff = GitWorktrees.fileDiff(path, file: file)
            await MainActor.run { if self.selectedFile == file.path { self.fileDiff = diff } }
        }
    }

    func createPR() async -> Result<String, Error> {
        creatingPR = true
        defer { creatingPR = false }
        let path = worktreePath, b = branch
        do { return .success(try await Task.detached { try GitWorktrees.createPR(path, branch: b) }.value) }
        catch { return .failure(error) }
    }

    func commit(message: String) async throws {
        let path = worktreePath
        try await Task.detached { try GitWorktrees.commit(path, message: message) }.value
        refreshDiff()
    }

    func terminateAll() { sessions.forEach { $0.terminate() } }
}

private struct PersistedWorkspace: Codable {
    var repoPath: String
    var branch: String
    var worktreePath: String
}

@MainActor
@Observable
final class WorkspaceModel {
    static let shared = WorkspaceModel()

    var workspaces: [Workspace] = []
    var selectedWorkspaceID: Workspace.ID?
    var installed: Set<AgentKind> = []

    private let storeKey = "agentWorkspaces"

    init() { load(); refreshInstalled() }

    /// Ensure the installed-agents set is populated (the UI populates it on appear,
    /// but the MCP bridge may run before any window has opened).
    func ensureInstalled() async {
        if installed.isEmpty {
            installed = await Task.detached { AgentDetector.detectInstalled() }.value
        }
    }

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    /// Restore workspaces from disk, dropping any whose worktree is gone.
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let items = try? JSONDecoder().decode([PersistedWorkspace].self, from: data) else { return }
        workspaces = items
            .filter { FileManager.default.fileExists(atPath: $0.worktreePath) }
            .map { Workspace(repoPath: $0.repoPath, branch: $0.branch, worktreePath: $0.worktreePath) }
        selectedWorkspaceID = workspaces.first?.id
        workspaces.forEach { $0.refreshDiff() }
    }

    private func persist() {
        let items = workspaces.map { PersistedWorkspace(repoPath: $0.repoPath, branch: $0.branch, worktreePath: $0.worktreePath) }
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: storeKey) }
    }

    func refreshInstalled() {
        Task.detached {
            let found = AgentDetector.detectInstalled()
            await MainActor.run { self.installed = found }
        }
    }

    /// `plain` → work directly in the chosen folder (no worktree, no new branch). Use for
    /// non-git roots with sub-repos, or to just open a repo in place. Otherwise a fresh
    /// isolated worktree is created on `branch`.
    @discardableResult
    func createWorkspace(repoPath: String, branch: String, plain: Bool = false) async throws -> Workspace {
        let path: String
        let actualBranch: String
        if plain {
            path = repoPath
            actualBranch = GitWorktrees.currentBranch(repoPath)   // "" for a non-git folder
        } else {
            path = try await Task.detached { try GitWorktrees.create(repoPath: repoPath, branch: branch) }.value
            actualBranch = branch
        }
        let workspace = Workspace(repoPath: repoPath, branch: actualBranch, worktreePath: path)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        persist()
        MCPConfig.wireWorktree(path)   // drop .mcp.json so agents here can orchestrate (no-op git steps on non-git)
        return workspace
    }

    func removeWorkspace(_ id: Workspace.ID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[idx]
        workspace.terminateAll()
        let repo = workspace.repoPath, path = workspace.worktreePath
        if path != repo {   // never delete the main checkout
            Task.detached { GitWorktrees.remove(repoPath: repo, worktreePath: path) }
        }
        workspaces.remove(at: idx)
        if selectedWorkspaceID == id { selectedWorkspaceID = workspaces.last?.id }
        persist()
    }

    func refreshDiffs() { workspaces.forEach { $0.refreshDiff() } }
}
