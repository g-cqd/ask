import AskAI
import Testing

@testable import AskAgentCore

/// A resumed session draws every tool call it holds (note n47): its input was decoded five times for one block, and a 60 MB session
/// spent a third of its resume there. `started` decodes once and says what the separate functions say.
@Suite("A tool call's start is read from its input once, and says what each part alone says")
struct ToolSummaryStartedTests {
    static let inputs = [
        #"{"command":"swift build","timeout_seconds":300,"yield_seconds":5}"#,
        #"{"command":"echo one\necho two"}"#,
        #"{"path":"Sources/a.swift","offset":10,"limit":20}"#,
        #"{"path":"notes.md","content":"hello\nworld"}"#,
        #"{"path":"a.swift","old_text":"let a = 1","new_text":"let a = 2"}"#,
        #"{"job":"job-3","action":"wait"}"#,
        #"{"questions":[{"question":"Which one?"},{"question":"And then?"}]}"#,
        #"{"name":"swift-testing","query":"expect"}"#,
        #"{"anything":["else",1,true]}"#
    ]

    @Test(arguments: inputs, ["bash", "read", "skill"])
    func `started says what header, fullInput, commandLimits and path say`(json: String, tool: String) throws {
        let input = try JSONObject(validating: Array(json.utf8))
        let started = ToolSummary.started(input, tool: tool)
        #expect(started.header == ToolSummary.header(for: input, tool: tool))
        #expect(started.fullInput == ToolSummary.fullInput(for: input))
        #expect(
            started.limits.map { [$0.timeout, $0.yield] }
                == ToolSummary.commandLimits(for: input).map { [$0.timeout, $0.yield] }
        )
        #expect(started.path == ToolSummary.path(for: input))
    }
}
