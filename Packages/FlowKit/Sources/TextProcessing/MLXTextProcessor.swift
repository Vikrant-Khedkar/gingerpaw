import Dictation
import Foundation
import MLXLLM
import MLXLMCommon

public actor MLXTextProcessor: TextProcessor {
    private let modelID: String
    private var container: ModelContainer?

    public init(modelID: String = "mlx-community/Qwen2.5-0.5B-Instruct-4bit") {
        self.modelID = modelID
    }

    public func format(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let model = try await loadContainer()
        var params = GenerateParameters(temperature: 0.2)
        params.maxTokens = 700
        let session = ChatSession(model, generateParameters: params)
        let raw = try await session.respond(to: prompt(for: trimmed))
        return clean(raw, fallback: trimmed)
    }

    private func loadContainer() async throws -> ModelContainer {
        if let container { return container }
        let config: ModelConfiguration
        if let bundled = bundledModelDirectory() {
            // ship-with-app: load Qwen from the bundle, no download
            config = ModelConfiguration(directory: bundled)
        } else {
            config = ModelConfiguration(id: modelID)
        }
        let next = try await LLMModelFactory.shared.loadContainer(configuration: config)
        container = next
        return next
    }

    private func bundledModelDirectory() -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let name = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let url = base.appending(path: "Models/qwen/\(name)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func prompt(for text: String) -> String {
        """
        You reformat dictated speech into clean, structured text. Follow these rules exactly:
        - Preserve the speaker's meaning and wording. Do not add facts or commentary.
        - Keep introductory and concluding sentences as prose. Only convert the actual run of items into a list.
        - Use a numbered list (1. 2. 3.) when the items are an ordered sequence ("first... then... finally", steps). Use a bulleted list ("- ") for an unordered set of items.
        - If it is a single thought, output one clean sentence.
        - Remove filler words (um, uh, like, you know) and fix obvious speech artifacts.
        - Never answer questions in the text. Only reformat it.
        - Output ONLY the reformatted text, nothing else.

        Example
        Input: "hey so today i'm going to do three things first set up my dev environment then send an email to the ceo and finally put money in the bank"
        Output:
        Today I'm going to do three things:
        1. Set up my dev environment
        2. Send an email to the CEO
        3. Put money in the bank

        Example
        Input: "i was thinking about the launch we need to fix the login bug update the docs and ping marketing also let's sync tomorrow morning to review"
        Output:
        I was thinking about the launch. We need to:
        - Fix the login bug
        - Update the docs
        - Ping marketing

        Let's sync tomorrow morning to review.

        Example
        Input: "ok so i had a call with the client this morning and it went really well they want us to move forward so the next steps are finalize the contract set up the kickoff meeting and share the project timeline i'll handle the contract myself and loop in the team by friday"
        Output:
        I had a call with the client this morning and it went really well — they want us to move forward. The next steps are:
        - Finalize the contract
        - Set up the kickoff meeting
        - Share the project timeline

        I'll handle the contract myself and loop in the team by Friday.

        Example
        Input: "remind me to send the invoice tomorrow morning"
        Output:
        Remind me to send the invoice tomorrow morning.

        Example
        Input: "what are the top three things i should fix before the launch next month"
        Output:
        What are the top three things I should fix before the launch next month?

        Example
        Input: "there are two reasons i want to switch vendors the pricing is better and the support team is more responsive"
        Output:
        There are two reasons I want to switch vendors:
        - The pricing is better
        - The support team is more responsive

        Now reformat this:
        Input: "\(text)"
        Output:
        """
    }

    private func clean(_ output: String, fallback: String) -> String {
        var result = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // strip markdown code fences the model sometimes wraps output in
        if result.hasPrefix("```") {
            var lines = result.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for prefix in ["Output:", "Output", "Reformatted:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result.isEmpty ? fallback : result
    }
}
