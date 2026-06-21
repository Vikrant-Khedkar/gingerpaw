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

    /// Binary probed on PATH and exec'd in the session.
    public var binary: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        case .cursor: "cursor-agent"
        }
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
