import Foundation

/// Reads a Claude Code transcript (JSONL) to find the line Claude wants spoken.
/// Convention: Claude ends a turn with `<say>one short line</say>`.
public enum Transcript {
    public static func sayMessage(transcriptPath: String) -> String? {
        guard let text = lastAssistantText(transcriptPath: transcriptPath) else { return nil }
        return extractSay(text)
    }

    /// Pull the last `<say>…</say>` payload out of a block of text.
    public static func extractSay(_ text: String) -> String? {
        guard let open = text.range(of: "<say>", options: .backwards),
              let close = text.range(of: "</say>", range: open.upperBound ..< text.endIndex)
        else { return nil }
        let inner = text[open.upperBound ..< close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    static func lastAssistantText(transcriptPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8)
        else { return nil }

        for line in content.split(separator: "\n").reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  isAssistant(obj),
                  let text = assistantText(obj)
            else { continue }
            return text
        }
        return nil
    }

    private static func isAssistant(_ obj: [String: Any]) -> Bool {
        if (obj["type"] as? String) == "assistant" { return true }
        if let message = obj["message"] as? [String: Any], (message["role"] as? String) == "assistant" { return true }
        return false
    }

    private static func assistantText(_ obj: [String: Any]) -> String? {
        let message = (obj["message"] as? [String: Any]) ?? obj
        if let string = message["content"] as? String { return string }
        if let blocks = message["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            let joined = texts.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}
