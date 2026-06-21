import SwiftTerm
import SwiftUI

/// One agent session: a live PTY terminal running an agent CLI in a directory.
/// The terminal is created (and the process started) once, then kept alive across
/// tab switches.
@MainActor
final class AgentSession: Identifiable {
    let id = UUID()
    let kind: AgentKind
    let directory: String
    let terminal: LocalProcessTerminalView

    init(kind: AgentKind, directory: String) {
        self.kind = kind
        self.directory = directory
        self.terminal = makeTerminal(directory: directory, command: kind.binary)
    }

    var folderName: String { (directory as NSString).lastPathComponent }

    func terminate() { terminal.terminate() }
}

@MainActor
@Observable
final class WorkspaceModel {
    var sessions: [AgentSession] = []
    var selectedID: AgentSession.ID?
    var installed: Set<AgentKind> = []

    func refreshInstalled() {
        Task.detached {
            let found = AgentDetector.detectInstalled()
            await MainActor.run { self.installed = found }
        }
    }

    func open(_ kind: AgentKind, directory: String) {
        let session = AgentSession(kind: kind, directory: directory)
        sessions.append(session)
        selectedID = session.id
    }

    func close(_ id: AgentSession.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].terminate()
        sessions.remove(at: idx)
        if selectedID == id { selectedID = sessions.last?.id }
    }
}
