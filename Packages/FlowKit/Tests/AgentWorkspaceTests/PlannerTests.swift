import Testing
@testable import AgentWorkspace

@Suite struct PlannerTests {
    @Test func parsesCleanJSONArray() {
        let out = #"Here is the plan: ["Add CONTRIBUTING.md", "Add LICENSE", "Add .editorconfig"]"#
        #expect(Planner.parse(out) == ["Add CONTRIBUTING.md", "Add LICENSE", "Add .editorconfig"])
    }

    @Test func parsesJSONWithSurroundingProse() {
        let out = "Sure.\n```json\n[\"task one\", \"task two\"]\n```\nDone."
        #expect(Planner.parse(out) == ["task one", "task two"])
    }

    @Test func fallsBackToBulletLines() {
        let out = "Plan:\n- first thing\n- second thing\n* third thing"
        #expect(Planner.parse(out) == ["first thing", "second thing", "third thing"])
    }

    @Test func fallsBackToNumberedLines() {
        let out = "1. alpha\n2. beta\n3) gamma"
        #expect(Planner.parse(out) == ["alpha", "beta", "gamma"])
    }

    @Test func emptyWhenNothingParseable() {
        #expect(Planner.parse("I could not produce a plan.").isEmpty)
    }

    @Test func parsePlanReadsSequentialMode() {
        let out = #"{"mode": "sequential", "subtasks": ["redesign landing", "screenshot it", "open PR"]}"#
        let plan = Planner.parsePlan(out)
        #expect(plan.mode == .sequential)
        #expect(plan.subtasks == ["redesign landing", "screenshot it", "open PR"])
    }

    @Test func parsePlanReadsParallelMode() {
        let out = "Sure:\n```json\n{\"mode\":\"parallel\",\"subtasks\":[\"a\",\"b\"]}\n```"
        let plan = Planner.parsePlan(out)
        #expect(plan.mode == .parallel)
        #expect(plan.subtasks == ["a", "b"])
    }

    @Test func parsePlanFallsBackToParallelArray() {
        let plan = Planner.parsePlan(#"["one", "two"]"#)
        #expect(plan.mode == .parallel)
        #expect(plan.subtasks == ["one", "two"])
    }
}
