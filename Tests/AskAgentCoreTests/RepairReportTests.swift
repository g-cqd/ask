import AskAI
import Testing

@testable import AskAgentCore

/// A session's repairs are said once, in words (the owner saw the same raw repair before every turn).
@Suite("Context repairs are reported once, for a person")
struct RepairReportTests {
    @Test func `a repair is reported the first time and not again`() {
        let reported = ReportedRepairs()
        #expect(reported.unreported([.interruptedToolCall(id: "a")]) == [.interruptedToolCall(id: "a")])
        #expect(reported.unreported([.interruptedToolCall(id: "a")]).isEmpty)
        #expect(
            reported.unreported([.interruptedToolCall(id: "a"), .orphanedToolResult(id: "b")])
                == [.orphanedToolResult(id: "b")], "only the new one")
    }

    @Test func `the description names each kind with its count, never the Swift value`() {
        #expect(
            RequestContext.describe([.interruptedToolCall(id: "toolu_1")])
                == "a tool call with no result was answered as interrupted")
        #expect(
            RequestContext.describe([
                .interruptedToolCall(id: "a"), .interruptedToolCall(id: "b"), .orphanedToolResult(id: "c"),
                .droppedBlock(type: "server_tool_use")
            ])
                == "2 tool calls with no result were answered as interrupted; a tool result whose call is gone was left out; "
                + "a block ask cannot send back (server_tool_use) was left out")
        #expect(!RequestContext.describe([.interruptedToolCall(id: "toolu_1")]).contains("toolu_1"))
    }
}
