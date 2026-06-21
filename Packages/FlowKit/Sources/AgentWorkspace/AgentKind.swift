import Foundation

/// A coding-agent CLI the workspace can launch.
public enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, cursor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        }
    }

    /// Binary probed on PATH.
    public var binary: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        case .cursor: "cursor-agent"
        }
    }

    /// Command exec'd in the session. Auto-approve flags (matching Superset) —
    /// safe because every session runs in its own isolated git worktree.
    public var launchCommand: String {
        switch self {
        // --mcp-config force-loads the worktree's .mcp.json (Claude won't auto-trust
        // a project MCP server otherwise). cwd is the worktree, so the path is relative.
        case .claude: "claude --dangerously-skip-permissions --mcp-config .mcp.json"
        case .codex: "codex --dangerously-bypass-approvals-and-sandbox"
        case .gemini: "gemini --approval-mode=auto_edit"
        case .cursor: "cursor-agent"
        }
    }

    /// Command form used when launching WITH an initial prompt. A trailing `--`
    /// terminates option parsing so the prompt is a clean positional — required for
    /// codex, and for claude because its variadic `--mcp-config` would otherwise
    /// swallow the prompt as another config path. Mirrors Superset.
    public var promptCommand: String {
        switch self {
        case .codex, .claude: launchCommand + " --"
        default: launchCommand
        }
    }

    /// Build the exec'd command, optionally baking in an initial prompt as an argv
    /// via a heredoc — Superset's approach: any prompt content (quotes, newlines)
    /// passes literally, and the agent starts working immediately. No PTY keystrokes.
    public func launch(prompt: String?) -> String {
        guard let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { return launchCommand }
        var delim = "GINGERPAW_PROMPT_EOF"
        while p.contains(delim) { delim += "_X" }
        return "\(promptCommand) \"$(cat <<'\(delim)'\n\(p)\n\(delim)\n)\""
    }

    /// Asset-catalog image name (bundled in the app).
    public var logo: String { "agent-\(rawValue)" }
}

/// Detects installed agent CLIs by probing PATH through a login shell — the same
/// way the user's terminal resolves npm/brew installs.
public enum AgentDetector {
    public static func detectInstalled() -> Set<AgentKind> {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let bins = AgentKind.allCases.map(\.binary).joined(separator: " ")
        let script = "for b in \(bins); do command -v $b >/dev/null 2>&1 && echo $b; done"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()

        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let present = Set(text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })
        return Set(AgentKind.allCases.filter { present.contains($0.binary) })
    }
}
