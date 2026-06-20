import Foundation
import Observation

@MainActor
@Observable
public final class PlaygroundController {
    public var rawPrompt = ""
    public var refinedPrompt = ""
    public var repositoryURL: URL?
    public private(set) var availability = AgentAvailability(isInstalled: false, detail: "claude-sgai not checked")
    public private(set) var status: AgentRunStatus = .idle
    public private(set) var output = ""
    public private(set) var runs: [AgentRun] = []

    @ObservationIgnored private let runner: any AgentRunning
    @ObservationIgnored private var runTask: Task<Void, Never>?

    public init(runner: any AgentRunning = ClaudeAgentRunner()) {
        self.runner = runner
    }

    public var canRun: Bool {
        availability.isInstalled &&
            !refinedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            repositoryURL != nil &&
            status != .running
    }

    public func checkClaude() {
        status = .checking
        Task {
            availability = await runner.checkAvailability()
            status = .idle
        }
    }

    public func useTranscript(_ transcript: String) {
        rawPrompt = transcript
        refinePrompt()
    }

    public func refinePrompt() {
        refinedPrompt = PromptRefiner.refine(rawPrompt)
    }

    public func run() {
        let prompt = refinedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard availability.isInstalled, !prompt.isEmpty, status != .running else { return }

        runTask?.cancel()
        output = ""
        status = .running
        var run = AgentRun(prompt: prompt, repositoryURL: repositoryURL, status: .running)
        runs.insert(run, at: 0)

        let request = AgentRunRequest(prompt: prompt, repositoryURL: repositoryURL)
        runTask = Task {
            do {
                for try await event in runner.run(request) {
                    switch event {
                    case let .output(text):
                        output += text
                        if let index = runs.firstIndex(where: { $0.id == run.id }) {
                            runs[index].output += text
                        }
                    case let .finished(exitCode):
                        run.endedAt = Date()
                        run.output = output
                        run.status = exitCode == 0 ? .succeeded : .failed("claude-sgai exited with code \(exitCode)")
                        status = run.status
                        if let index = runs.firstIndex(where: { $0.id == run.id }) {
                            runs[index] = run
                        }
                    }
                }
            } catch {
                let message = String(describing: error)
                run.endedAt = Date()
                run.output = output
                run.status = .failed(message)
                status = run.status
                if let index = runs.firstIndex(where: { $0.id == run.id }) {
                    runs[index] = run
                }
            }
        }
    }

    public func cancel() {
        runTask?.cancel()
        runTask = nil
        status = .idle
    }
}
