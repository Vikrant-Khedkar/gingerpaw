import Foundation
import Playground
import Testing

@Test
func promptRefinerRemovesLeadingFillersAndAddsTaskFrame() {
    let refined = PromptRefiner.refine("um okay add transcript history")

    #expect(refined.hasPrefix("Add transcript history."))
    #expect(refined.contains("Work in the selected repository."))
}

@MainActor
@Test
func controllerRunsClaudeTaskAndRecordsHistory() async throws {
    let controller = PlaygroundController(runner: StubRunner())
    controller.repositoryURL = URL(fileURLWithPath: "/tmp/project")
    controller.rawPrompt = "add playground"
    controller.refinePrompt()
    controller.checkClaude()

    try await waitUntil { controller.availability.isInstalled }
    #expect(controller.canRun)

    controller.run()
    try await waitUntil { controller.status == .succeeded }

    #expect(controller.output == "done")
    #expect(controller.runs.first?.status == .succeeded)
    #expect(controller.runs.first?.repositoryURL?.path == "/tmp/project")
}

private struct StubRunner: AgentRunning {
    func checkAvailability() async -> AgentAvailability {
        AgentAvailability(isInstalled: true, detail: "Claude 1.0")
    }

    func run(_: AgentRunRequest) -> AsyncThrowingStream<AgentRunEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.output("done"))
            continuation.yield(.finished(exitCode: 0))
            continuation.finish()
        }
    }
}

private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<50 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(Bool(false))
}
