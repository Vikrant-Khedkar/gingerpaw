import Foundation

/// Internal localhost RPC contract between `gingerpaw-cli mcp` and the running app.
/// Framed as NDJSON (one JSON object per line). NOT the MCP wire format — the CLI
/// translates MCP tool calls into these.

public enum IPCMethod: String, Codable, Sendable {
    case listWorkspaces, createWorkspace, openSession, readDiff, readSessionOutput
}

public struct IPCRequest: Codable, Sendable {
    public let id: Int
    public let token: String
    public let method: IPCMethod
    public var repoPath: String?
    public var branch: String?
    public var agent: String?
    public var prompt: String?
    public var workspaceId: String?
    public var sessionId: String?
    public var maxLines: Int?

    public init(id: Int, token: String, method: IPCMethod,
                repoPath: String? = nil, branch: String? = nil, agent: String? = nil,
                prompt: String? = nil, workspaceId: String? = nil, sessionId: String? = nil, maxLines: Int? = nil) {
        self.id = id; self.token = token; self.method = method
        self.repoPath = repoPath; self.branch = branch; self.agent = agent
        self.prompt = prompt; self.workspaceId = workspaceId; self.sessionId = sessionId; self.maxLines = maxLines
    }
}

public struct IPCSession: Codable, Sendable {
    public let id: String
    public let agent: String
    public init(id: String, agent: String) { self.id = id; self.agent = agent }
}

public struct IPCWorkspace: Codable, Sendable {
    public let id: String
    public let repoName: String
    public let repoPath: String
    public let branch: String
    public let worktreePath: String
    public let insertions: Int
    public let deletions: Int
    public let files: Int
    public let sessions: [IPCSession]
    public init(id: String, repoName: String, repoPath: String, branch: String, worktreePath: String,
                insertions: Int, deletions: Int, files: Int, sessions: [IPCSession]) {
        self.id = id; self.repoName = repoName; self.repoPath = repoPath; self.branch = branch
        self.worktreePath = worktreePath; self.insertions = insertions; self.deletions = deletions
        self.files = files; self.sessions = sessions
    }
}

public struct IPCFile: Codable, Sendable {
    public let path: String
    public let status: String
    public let insertions: Int
    public let deletions: Int
    public init(path: String, status: String, insertions: Int, deletions: Int) {
        self.path = path; self.status = status; self.insertions = insertions; self.deletions = deletions
    }
}

public struct IPCResult: Codable, Sendable {
    public var workspaces: [IPCWorkspace]?
    public var workspaceId: String?
    public var sessionId: String?
    public var files: [IPCFile]?
    public var diff: String?
    public var output: String?
    public var message: String?
    public init(workspaces: [IPCWorkspace]? = nil, workspaceId: String? = nil, sessionId: String? = nil,
                files: [IPCFile]? = nil, diff: String? = nil, output: String? = nil, message: String? = nil) {
        self.workspaces = workspaces; self.workspaceId = workspaceId; self.sessionId = sessionId
        self.files = files; self.diff = diff; self.output = output; self.message = message
    }
}

public struct IPCResponse: Codable, Sendable {
    public let id: Int
    public let ok: Bool
    public var result: IPCResult?
    public var error: String?
    public init(id: Int, ok: Bool, result: IPCResult? = nil, error: String? = nil) {
        self.id = id; self.ok = ok; self.result = result; self.error = error
    }
}

/// `~/.gingerpaw/mcp.json` — how the CLI discovers the app's loopback port + auth token.
public struct MCPPortFile: Codable, Sendable {
    public let port: UInt16
    public let token: String
    public init(port: UInt16, token: String) { self.port = port; self.token = token }

    public static var path: String {
        NSHomeDirectory() + "/.gingerpaw/mcp.json"
    }
}
