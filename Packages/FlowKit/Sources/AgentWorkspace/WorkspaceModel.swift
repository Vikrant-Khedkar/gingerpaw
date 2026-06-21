import SwiftTerm
import SwiftUI

/// One agent session: a live PTY terminal running an agent CLI in a worktree.
@MainActor
final class AgentSession: Identifiable {
    let id = UUID()
    let kind: AgentKind
    let terminal: LocalProcessTerminalView

    init(kind: AgentKind, directory: String, prompt: String? = nil) {
        self.kind = kind
        self.terminal = makeTerminal(directory: directory, command: kind.launch(prompt: prompt))
    }

    func terminate() { terminal.terminate() }

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

    init(repoPath: String, branch: String, worktreePath: String) {
        self.repoPath = repoPath
        self.branch = branch
        self.worktreePath = worktreePath
    }

    var repoName: String { (repoPath as NSString).lastPathComponent }

    func openSession(_ kind: AgentKind, prompt: String? = nil) {
        MCPConfig.wireWorktree(worktreePath)   // ensure .mcp.json exists before launch
        let session = AgentSession(kind: kind, directory: worktreePath, prompt: prompt)
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
            await MainActor.run {
                self.diff = stat
                self.changes = files
                self.ports = ports
                self.ahead = ab?.ahead ?? 0
                self.behind = ab?.behind ?? 0
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

    @discardableResult
    func createWorkspace(repoPath: String, branch: String) async throws -> Workspace {
        let path = try await Task.detached {
            try GitWorktrees.create(repoPath: repoPath, branch: branch)
        }.value
        let workspace = Workspace(repoPath: repoPath, branch: branch, worktreePath: path)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        persist()
        MCPConfig.wireWorktree(path)   // drop .mcp.json so agents here can orchestrate
        return workspace
    }

    func removeWorkspace(_ id: Workspace.ID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[idx]
        workspace.terminateAll()
        let repo = workspace.repoPath, path = workspace.worktreePath
        Task.detached { GitWorktrees.remove(repoPath: repo, worktreePath: path) }
        workspaces.remove(at: idx)
        if selectedWorkspaceID == id { selectedWorkspaceID = workspaces.last?.id }
        persist()
    }

    func refreshDiffs() { workspaces.forEach { $0.refreshDiff() } }
}
