import AgentMCP
import Foundation
import Network
import Security

/// Loopback IPC server the bundled `gingerpaw-cli mcp` connects to. Translates
/// IPC requests into operations on the shared WorkspaceModel (on the MainActor),
/// so an agent can drive the cockpit. Token-gated, loopback-only.
@MainActor
public final class MCPBridgeServer {
    public static let shared = MCPBridgeServer()
    private var listener: NWListener?
    private let token = MCPBridgeServer.randomToken()
    private let maxSessions = 8

    public init() {}

    public func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else { return }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = listener.port?.rawValue { Task { @MainActor in self?.writePortFile(port) } }
            case .failed, .cancelled:
                Task { @MainActor in self?.removePortFile() }
            default: break
            }
        }
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global(qos: .userInitiated))
            MCPBridgeServer.receive(conn, buffer: Data())
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    // MARK: Connection framing (NDJSON)

    private nonisolated static func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            while let nl = buf.firstIndex(of: 0x0a) {
                let line = Data(buf[buf.startIndex..<nl])
                buf.removeSubrange(buf.startIndex...nl)
                if let req = try? JSONDecoder().decode(IPCRequest.self, from: line) {
                    Task { @MainActor in
                        let resp = await MCPBridgeServer.shared.respond(req)
                        if var out = try? JSONEncoder().encode(resp) {
                            out.append(0x0a)
                            conn.send(content: out, completion: .contentProcessed { _ in })
                        }
                    }
                }
            }
            if isComplete || error != nil { conn.cancel() }
            else { receive(conn, buffer: buf) }
        }
    }

    private func respond(_ req: IPCRequest) async -> IPCResponse {
        guard req.token == token else { return IPCResponse(id: req.id, ok: false, error: "unauthorized") }
        return await route(req)
    }

    // MARK: Router

    private func route(_ req: IPCRequest) async -> IPCResponse {
        let model = WorkspaceModel.shared
        switch req.method {
        case .listWorkspaces:
            let list = model.workspaces.map { ws in
                IPCWorkspace(id: ws.id.uuidString, repoName: ws.repoName, repoPath: ws.repoPath, branch: ws.branch,
                             worktreePath: ws.worktreePath, insertions: ws.diff.insertions, deletions: ws.diff.deletions,
                             files: ws.diff.files, sessions: ws.sessions.map { IPCSession(id: $0.id.uuidString, agent: $0.kind.rawValue) })
            }
            return IPCResponse(id: req.id, ok: true, result: IPCResult(workspaces: list))

        case .createWorkspace:
            guard let repo = req.repoPath, let branch = req.branch else { return err(req, "repoPath and branch required") }
            guard GitWorktrees.isGitRepo(repo) else { return err(req, "Not a git repository: \(repo)") }
            await model.ensureInstalled()
            guard let agent = agentKind(req, model) else { return err(req, "agent not installed: \(req.agent ?? "?")") }
            guard liveSessions(model) < maxSessions else { return err(req, "session limit reached (\(maxSessions))") }
            do {
                let ws = try await model.createWorkspace(repoPath: repo, branch: branch)
                AgentWorkspaceWindow.show()   // mount the terminal so the PTY gets a real size
                ws.openSession(agent, prompt: req.prompt)
                return IPCResponse(id: req.id, ok: true, result: IPCResult(workspaceId: ws.id.uuidString, sessionId: ws.sessions.last?.id.uuidString))
            } catch { return err(req, "\(error)") }

        case .openSession:
            guard let ws = workspace(req.workspaceId, model) else { return err(req, "workspace not found") }
            await model.ensureInstalled()
            guard let agent = agentKind(req, model) else { return err(req, "agent not installed: \(req.agent ?? "?")") }
            guard liveSessions(model) < maxSessions else { return err(req, "session limit reached (\(maxSessions))") }
            AgentWorkspaceWindow.show()
            ws.openSession(agent, prompt: req.prompt)
            return IPCResponse(id: req.id, ok: true, result: IPCResult(sessionId: ws.sessions.last?.id.uuidString))

        case .readDiff:
            guard let ws = workspace(req.workspaceId, model) else { return err(req, "workspace not found") }
            await ws.refreshDiffAndWait()
            let files = ws.changes.map { IPCFile(path: $0.path, status: $0.status, insertions: $0.insertions, deletions: $0.deletions) }
            return IPCResponse(id: req.id, ok: true, result: IPCResult(files: files, diff: ws.fullDiff))

        case .readSessionOutput:
            guard let ws = workspace(req.workspaceId, model) else { return err(req, "workspace not found") }
            guard let sid = req.sessionId.flatMap({ UUID(uuidString: $0) }),
                  let s = ws.sessions.first(where: { $0.id == sid }) else { return err(req, "session not found") }
            return IPCResponse(id: req.id, ok: true, result: IPCResult(output: s.snapshot(maxLines: req.maxLines ?? 40)))
        }
    }

    // MARK: Helpers

    private func liveSessions(_ model: WorkspaceModel) -> Int { model.workspaces.reduce(0) { $0 + $1.sessions.count } }
    private func agentKind(_ req: IPCRequest, _ model: WorkspaceModel) -> AgentKind? {
        let kind = AgentKind(rawValue: req.agent ?? "claude") ?? .claude
        return model.installed.contains(kind) ? kind : nil
    }
    private func workspace(_ idStr: String?, _ model: WorkspaceModel) -> Workspace? {
        guard let idStr, let id = UUID(uuidString: idStr) else { return nil }
        return model.workspaces.first { $0.id == id }
    }
    private func err(_ req: IPCRequest, _ msg: String) -> IPCResponse { IPCResponse(id: req.id, ok: false, error: msg) }

    private func writePortFile(_ port: UInt16) {
        let dir = NSHomeDirectory() + "/.gingerpaw"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(MCPPortFile(port: port, token: token)) else { return }
        try? data.write(to: URL(fileURLWithPath: MCPPortFile.path))
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: MCPPortFile.path)
    }
    private func removePortFile() { try? FileManager.default.removeItem(atPath: MCPPortFile.path) }

    private nonisolated static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
