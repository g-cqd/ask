import AskAI
import Testing

@testable import AskAgentCore

/// Agent turns in the session: a whole assistant response and each tool result, pinned on the wire and
/// replayed exactly.
@Suite("Agent turns persist exactly and replay unchanged")
struct AgentPayloadTests {
    private let response = AssembledResponse(
        id: "msg_1", model: "claude-x",
        blocks: [
            .thinking(text: "Look first.", signature: "sig=="), .redactedThinking(data: "opaque"), .text("Reading."),
            .toolCall(
                id: "toolu_1", name: "read", input: try! JSONObject(validating: Array(#"{"path": "a.swift"}"#.utf8))),
            .unrecognized(type: "server_tool_use")
        ],
        stopReason: .toolUse, usage: TokenUsage(input: 25, output: 40, cacheRead: 7), unrecognized: [])

    @Test func `a response and a tool result are pinned on the wire`() throws {
        var tree = SessionTree()
        let call = try tree.append(.response(response))
        _ = try tree.append(.toolResult(callID: "toolu_1", content: "let a = 1", isError: false))
        let lines = try SessionLog.snapshot(tree).split(separator: 0x0A).map { String(decoding: $0, as: UTF8.self) }
        #expect(
            lines[1] == #"{"id":"0","payload":{"blocks":[{"signature":"sig==","text":"Look first.","type":"thinking"},"#
                + #"{"data":"opaque","type":"redacted_thinking"},{"text":"Reading.","type":"text"},"#
                + #"{"id":"toolu_1","input":"{\"path\": \"a.swift\"}","name":"read","type":"tool_call"},"#
                + #"{"name":"server_tool_use","type":"unrecognized"}],"id":"msg_1","kind":"response","model":"claude-x","#
                + #""stopReason":"tool_use","usage":{"cacheRead":7,"input":25,"output":40}},"type":"entry"}"#)
        #expect(
            lines[2] == #"{"id":"1","parent":"\#(call)","payload":{"callID":"toolu_1","content":"let a = 1","#
                + #""isError":false,"kind":"tool_result"},"type":"entry"}"#)
    }

    @Test func `agent turns round-trip unchanged`() throws {
        var tree = SessionTree()
        _ = try tree.append(.user("go"))
        _ = try tree.append(.response(response))
        _ = try tree.append(.toolResult(callID: "toolu_1", content: "no such file", isError: true))
        var bare = response
        bare.stopReason = nil
        bare.usage = TokenUsage()
        _ = try tree.append(.response(bare))
        let decoded = try SessionLog.decode(SessionLog.snapshot(tree))
        #expect(decoded.entries == tree.entries)
    }

    @Test(arguments: [
        #"{"id":"t","input":"[1]","name":"read","type":"tool_call"}"#,
        #"{"text":"x","type":"mystery"}"#,
        #"{"type":"thinking","text":"no signature"}"#
    ])
    func `a block this version cannot replay is a damaged line, not a guess`(block: String) throws {
        let bytes = Array(
            ("{\"type\":\"session\",\"version\":1}\n"
                + #"{"id":"0","payload":{"blocks":["# + block + #"],"id":"m","#
                + #""kind":"response","model":"c","usage":{}},"type":"entry"}"# + "\n")
                .utf8)
        let recovered = try SessionLog.recover(bytes)
        #expect(recovered.tree.entries.isEmpty)
        #expect(!recovered.issues.isEmpty)
    }
}
