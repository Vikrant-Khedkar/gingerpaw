import Foundation

/// A Claude Code lifecycle event we can speak about.
public enum AgentEvent: String, CaseIterable, Sendable {
    case stop
    case notification
    case subagentStop
}

public enum AgentMessage {
    /// Short spoken line for an event, given the hook's JSON payload. Returns nil to stay silent.
    public static func text(for event: AgentEvent, payload: [String: Any]) -> String? {
        switch event {
        case .stop:
            if let project = projectName(payload) {
                return "Claude finished in \(project)."
            }
            return "Claude finished."
        case .subagentStop:
            return "A subtask finished."
        case .notification:
            if let message = payload["message"] as? String, !message.isEmpty {
                return shorten(message)
            }
            return "Claude needs your attention."
        }
    }

    private static func projectName(_ payload: [String: Any]) -> String? {
        guard let cwd = payload["cwd"] as? String, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Keep spoken notifications brief.
    private static func shorten(_ text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
