import SwiftTerm
import SwiftUI

/// One agent session: a live PTY terminal running an agent CLI in a worktree.
@MainActor
final class AgentSession: Identifiable {
    let id = UUID()
    let kind: AgentKind
    let terminal: LocalProcessTerminalView

    init(kind: AgentKind, directory: String) {
        self.kind = kind
        self.terminal = makeTerminal(directory: directory, command: kind.launchCommand)
    }

    func terminate() { terminal.terminate() }
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

    init(repoPath: String, branch: String, worktreePath: String) {
        self.repoPath = repoPath
        self.branch = branch
        self.worktreePath = worktreePath
    }

    var repoName: String { (repoPath as NSString).lastPathComponent }

    func openSession(_ kind: AgentKind) {
        let session = AgentSession(kind: kind, directory: worktreePath)
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
            let stat = GitWorktrees.diffStat(path)
            await MainActor.run { self.diff = stat }
        }
    }

    func terminateAll() { sessions.forEach { $0.terminate() } }
}

@MainActor
@Observable
final class WorkspaceModel {
    var workspaces: [Workspace] = []
    var selectedWorkspaceID: Workspace.ID?
    var installed: Set<AgentKind> = []

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    func refreshInstalled() {
        Task.detached {
            let found = AgentDetector.detectInstalled()
            await MainActor.run { self.installed = found }
        }
    }

    func createWorkspace(repoPath: String, branch: String) async throws {
        let path = try await Task.detached {
            try GitWorktrees.create(repoPath: repoPath, branch: branch)
        }.value
        let workspace = Workspace(repoPath: repoPath, branch: branch, worktreePath: path)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
    }

    func removeWorkspace(_ id: Workspace.ID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[idx]
        workspace.terminateAll()
        let repo = workspace.repoPath, path = workspace.worktreePath
        Task.detached { GitWorktrees.remove(repoPath: repo, worktreePath: path) }
        workspaces.remove(at: idx)
        if selectedWorkspaceID == id { selectedWorkspaceID = workspaces.last?.id }
    }

    func refreshDiffs() { workspaces.forEach { $0.refreshDiff() } }
}
