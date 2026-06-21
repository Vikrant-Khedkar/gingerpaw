import AgentMCP
import Foundation

/// Minimal hand-rolled MCP server over stdio (line-delimited JSON-RPC). Translates
/// `tools/call` into IPC requests to the running GingerPaw app over loopback TCP.
/// stdout is the protocol channel — all logging goes to stderr.
final class MCPServer {
    private var reqCounter = 0

    func run() {
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            handle(msg)
        }
    }

    private func handle(_ msg: [String: Any]) {
        let method = msg["method"] as? String ?? ""
        let id = msg["id"]
        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "gingerpaw", "version": "0.1.0"],
            ])
        case "notifications/initialized", "initialized":
            break
        case "ping":
            respond(id: id, result: [String: Any]())
        case "tools/list":
            respond(id: id, result: ["tools": Self.toolSchemas])
        case "tools/call":
            let params = msg["params"] as? [String: Any] ?? [:]
            callTool(id: id, name: params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            if id != nil { respondError(id: id, code: -32601, message: "method not found: \(method)") }
        }
    }

    private func callTool(id: Any?, name: String, arguments: [String: Any]) {
        let method: IPCMethod
        switch name {
        case "list_workspaces": method = .listWorkspaces
        case "create_workspace": method = .createWorkspace
        case "open_session": method = .openSession
        case "read_diff": method = .readDiff
        case "read_session_output": method = .readSessionOutput
        default: toolError(id: id, "unknown tool: \(name)"); return
        }
        guard let pf = MCPClient.portFile() else {
            toolError(id: id, "GingerPaw is not running. Open the app and try again."); return
        }
        reqCounter += 1
        let req = IPCRequest(id: reqCounter, token: pf.token, method: method,
                             repoPath: arguments["repo"] as? String,
                             branch: arguments["branch"] as? String,
                             agent: arguments["agent"] as? String,
                             prompt: arguments["prompt"] as? String,
                             workspaceId: arguments["workspaceId"] as? String,
                             sessionId: arguments["sessionId"] as? String,
                             maxLines: arguments["maxLines"] as? Int)
        guard let resp = MCPClient.send(req, port: pf.port) else {
            toolError(id: id, "Couldn't reach GingerPaw."); return
        }
        if resp.ok {
            respond(id: id, result: ["content": [["type": "text", "text": Self.resultText(resp.result)]], "isError": false])
        } else {
            toolError(id: id, resp.error ?? "error")
        }
    }

    private static func resultText(_ r: IPCResult?) -> String {
        guard let r else { return "ok" }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let d = try? enc.encode(r), let s = String(data: d, encoding: .utf8) { return s }
        return "ok"
    }

    // MARK: stdout writers

    private func respond(id: Any?, result: [String: Any]) {
        guard let id else { return }
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }
    private func respondError(id: Any?, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }
    private func toolError(id: Any?, _ message: String) {
        respond(id: id, result: ["content": [["type": "text", "text": message]], "isError": true])
    }
    private func write(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: tool schemas

    private static var toolSchemas: [[String: Any]] { [
        [
            "name": "list_workspaces",
            "description": "List GingerPaw workspaces (each a git worktree on its own branch) with their diff stats and running agent sessions.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "create_workspace",
            "description": "Create a new workspace: a git worktree on its own branch off a repo, then launch an agent in it. Optionally pass an initial prompt the agent starts working on.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "repo": ["type": "string", "description": "Absolute path to an existing git repository."],
                    "branch": ["type": "string", "description": "Branch name for the new worktree (created if missing)."],
                    "agent": ["type": "string", "enum": ["claude", "codex", "gemini", "cursor"], "description": "Agent to launch."],
                    "prompt": ["type": "string", "description": "Optional task fed to the agent on start."],
                ],
                "required": ["repo", "branch", "agent"],
            ],
        ],
        [
            "name": "open_session",
            "description": "Launch another agent session inside an existing workspace's worktree. Optionally pass an initial prompt.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workspaceId": ["type": "string"],
                    "agent": ["type": "string", "enum": ["claude", "codex", "gemini", "cursor"]],
                    "prompt": ["type": "string"],
                ],
                "required": ["workspaceId", "agent"],
            ],
        ],
        [
            "name": "read_diff",
            "description": "Read the changed files and full diff vs HEAD for a workspace's worktree — use this to inspect what an agent has done.",
            "inputSchema": [
                "type": "object",
                "properties": ["workspaceId": ["type": "string"]],
                "required": ["workspaceId"],
            ],
        ],
        [
            "name": "read_session_output",
            "description": "Scrape the current visible terminal screen of an agent session (raw rendered text).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workspaceId": ["type": "string"],
                    "sessionId": ["type": "string"],
                    "maxLines": ["type": "integer", "description": "How many recent lines to return (default 40)."],
                ],
                "required": ["workspaceId", "sessionId"],
            ],
        ],
    ] }
}

/// Loopback TCP client to the app's MCPBridgeServer (one request/response per call).
enum MCPClient {
    static func portFile() -> MCPPortFile? {
        guard let data = FileManager.default.contents(atPath: MCPPortFile.path) else { return nil }
        return try? JSONDecoder().decode(MCPPortFile.self, from: data)
    }

    static func send(_ req: IPCRequest, port: UInt16) -> IPCResponse? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return nil }

        guard var payload = try? JSONEncoder().encode(req) else { return nil }
        payload.append(0x0a)
        _ = payload.withUnsafeBytes { raw in Foundation.write(fd, raw.baseAddress, raw.count) }

        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = Foundation.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buf.append(contentsOf: chunk[0..<n])
            if buf.contains(0x0a) { break }
        }
        let line = buf.firstIndex(of: 0x0a).map { buf[..<$0] } ?? buf[...]
        return try? JSONDecoder().decode(IPCResponse.self, from: Data(line))
    }
}
