import AemiJSON
import AskAI
import Testing

@testable import AskAgentCore

/// `ask -p --json` (roadmap 0234): each event of a run as one JSON object on a line, with a version, for scripts and other front ends.
@Suite("A run's events as JSON lines")
struct JSONEventWriterTests {
    private func lines(_ events: [AgentEvent]) -> [String] {
        let writer = JSONEventWriter()
        return events.flatMap { writer.lines(for: $0) }
    }

    /// The parsed line; the document is kept with it, since a `JSON` node reads from its document.
    private func object(_ line: String) throws -> JSON {
        try AemiJSON.parse(Array(line.utf8)).root
    }

    @Test func `text, thinking, tool calls and results, the response and the end are each one line with a version`()
        throws
    {
        let input = try JSONObject(validating: Array(#"{"command":"ls \"a b\""}"#.utf8))
        let response = AssembledResponse(
            id: "r",
            model: "m",
            blocks: [],
            stopReason: .toolUse,
            usage: TokenUsage(input: 12, output: 3),
            unrecognized: []
        )
        let found = lines([
            .model(.textDelta(index: 0, "He said \"hi\"\n")),
            .model(.thinkingDelta(index: 1, "hmm")),
            .toolStarted(id: "c1", name: "bash", input: input),
            .toolFinished(id: "c1", name: "bash", output: ToolOutput("a\nb", isError: false)),
            .responded(response),
            .retrying(attempt: 1, of: 3, delay: .milliseconds(1500), reason: "overloaded"),
            .finished(.endTurn)
        ])
        #expect(found.count == 7)
        #expect(found.allSatisfy { !$0.contains("\n") }, "one line each")
        let parsed = try found.map(object)
        #expect(parsed.allSatisfy { $0["v"].int == 1 })
        #expect(
            parsed.map { $0["type"].string ?? "" } == [
                "text", "thinking", "tool_call", "tool_result", "response", "retry", "finished"
            ]
        )
        #expect(parsed[0]["text"].string == "He said \"hi\"\n")
        #expect(parsed[2]["input"]["command"].string == "ls \"a b\"", "the tool's input is JSON, not a string")
        #expect(parsed[3]["content"].string == "a\nb" && parsed[3]["is_error"].bool == false)
        #expect(parsed[4]["stop_reason"].string == "tool_use" && parsed[4]["usage"]["input"].int == 12)
        #expect(parsed[5]["delay_ms"].int == 1500)
        #expect(parsed[6]["stop_reason"].string == "end_turn")
    }

    @Test func `the end line names the session and the usage`() throws {
        let line = JSONEventWriter().endLine(session: "/s/x.jsonl", usage: TokenUsage(input: 5, output: 2))
        let parsed = try object(line)
        #expect(
            parsed["type"].string == "end" && parsed["session"].string == "/s/x.jsonl"
                && parsed["usage"]["output"].int == 2
        )
    }

    @Test func `deltas that carry nothing and events of no use outside give no line`() {
        #expect(lines([.model(.signatureDelta(index: 0, "sig")), .model(.blockStopped(index: 0))]).isEmpty)
    }
}
