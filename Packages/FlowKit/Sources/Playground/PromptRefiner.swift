import Foundation

public enum PromptRefiner {
    public static func refine(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var words = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let fillers: Set<String> = ["um", "uh", "like", "okay", "ok", "so"]
        while let first = words.first?.lowercased().trimmingCharacters(in: .punctuationCharacters),
              fillers.contains(first) {
            words.removeFirst()
        }

        var sentence = words.joined(separator: " ")
        if let first = sentence.first {
            sentence.replaceSubrange(sentence.startIndex...sentence.startIndex, with: String(first).uppercased())
        }
        if !sentence.hasSuffix(".") && !sentence.hasSuffix("?") && !sentence.hasSuffix("!") {
            sentence += "."
        }

        return """
        \(sentence)

        Work in the selected repository. Explain the approach briefly, make the necessary code changes, and run the relevant build or tests before summarizing the result.
        """
    }
}
