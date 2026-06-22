import Testing
@testable import AgentWorkspace

@Suite struct StreamEventTests {
    @Test func parsesToolUseIntoActivity() {
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/routes/upload.ts","old_string":"a","new_string":"b"}}]}}"#
        let ev = StreamEvent.decode(line: line)
        #expect(ev?.type == "assistant")
        let block = ev?.message?.content.first
        #expect(block?.type == "tool_use")
        #expect(AgentRun.activityLine(tool: block?.name, input: block?.input) == "Editing upload.ts")
        #expect(AgentRun.icon(tool: block?.name) == "pencil")
    }

    @Test func parsesBashCommand() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}"#
        let block = StreamEvent.decode(line: line)?.message?.content.first
        #expect(AgentRun.activityLine(tool: block?.name, input: block?.input) == "Running swift test")
    }

    @Test func parsesResultSummary() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"Added rate limiting to /upload.","duration_ms":4200,"total_cost_usd":0.01}"#
        let ev = StreamEvent.decode(line: line)
        #expect(ev?.type == "result")
        #expect(ev?.isError == false)
        #expect(ev?.result == "Added rate limiting to /upload.")
    }

    @Test func tolueratesTextBlocksAndNestedInput() {
        // text block + a tool with a nested-object input field that must not break decoding
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the routes."},{"type":"tool_use","name":"Read","input":{"file_path":"a.ts","extra":{"nested":true}}}]}}"#
        let blocks = StreamEvent.decode(line: line)?.message?.content
        #expect(blocks?.count == 2)
        #expect(blocks?.first?.text == "Looking at the routes.")
        #expect(AgentRun.activityLine(tool: blocks?.last?.name, input: blocks?.last?.input) == "Reading a.ts")
    }

    @Test func garbageLineIsNil() {
        #expect(StreamEvent.decode(line: "not json at all") == nil)
        #expect(StreamEvent.decode(line: "") == nil)
    }
}
