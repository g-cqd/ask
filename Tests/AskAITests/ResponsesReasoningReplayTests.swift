internal import Foundation
internal import Testing

@testable import AskAI

/// Reasoning the server sealed is sent back inside the tool loop that produced it, and nowhere else (ADR-0062).
struct ResponsesReasoningReplayTests {
    private static let replaying = ResponsesDialect(sendsOutputLimit: false, replaysReasoning: true)

    private static func sealed(_ id: String, _ summary: [String] = ["thought"], _ content: String = "SEALED") -> String
    {
        ReasoningProvenance.mark(
            scheme: "responses",
            payload: ResponsesStreamDecoder.reasoningPayload(id: id, summaries: summary, sealed: content))
    }

    private static func item(_ id: String, _ summary: [String] = ["thought"], _ content: String = "SEALED") -> String {
        ResponsesStreamDecoder.reasoningPayload(id: id, summaries: summary, sealed: content)
    }

    private func call(_ id: String) throws -> RequestBlock {
        .toolCall(id: id, name: "read", input: try JSONObject(validating: Array(#"{"path":"x"}"#.utf8)))
    }

    private func encode(_ messages: [ModelMessage], dialect: ResponsesDialect = replaying) -> String {
        let request = ModelRequest(model: "m", maxTokens: 10, systemPrompt: [], messages: messages, tools: [])
        return String(decoding: ResponsesRequestEncoder.encode(request, dialect: dialect), as: UTF8.self)
    }

    private func input(_ body: String) -> String {
        let start = body.range(of: #""input":["#)!.upperBound
        let end = body.range(of: #"],"tool"#) ?? body.range(of: #"]}"#, options: .backwards)!
        return String(body[start ..< end.lowerBound])
    }

    private let prompt = ModelMessage(role: .user, blocks: [.text("go")])
    private func result(_ id: String) -> ModelMessage {
        ModelMessage(role: .user, blocks: [.toolResult(id: id, content: "data", isError: false)])
    }

    @Test func `reasoning from the current tool loop goes back, in order, before its call`() throws {
        let messages = [
            prompt,
            ModelMessage(
                role: .assistant, blocks: [.thinking(text: "t", signature: Self.sealed("rs_1")), try call("c1")]),
            result("c1")
        ]
        #expect(
            input(encode(messages))
                == #"{"role":"user","content":[{"type":"input_text","text":"go"}]},"#
                + Self.item("rs_1") + #","#
                + #"{"type":"function_call","call_id":"c1","name":"read","arguments":"{\"path\":\"x\"}"},"#
                + #"{"type":"function_call_output","call_id":"c1","output":"data"}"#)
    }

    @Test func `two reasoning items and a text run keep the order the model produced them`() throws {
        let messages = [
            prompt,
            ModelMessage(
                role: .assistant,
                blocks: [
                    .text("first"), .thinking(text: "", signature: Self.sealed("rs_1", [], "A")),
                    .thinking(text: "", signature: Self.sealed("rs_2", ["s"], "B")), try call("c1")
                ]),
            result("c1")
        ]
        #expect(
            input(encode(messages))
                == #"{"role":"user","content":[{"type":"input_text","text":"go"}]},"#
                + #"{"role":"assistant","content":"first"},"# + Self.item("rs_1", [], "A") + #","#
                + Self.item("rs_2", ["s"], "B") + #","#
                + #"{"type":"function_call","call_id":"c1","name":"read","arguments":"{\"path\":\"x\"}"},"#
                + #"{"type":"function_call_output","call_id":"c1","output":"data"}"#)
    }

    @Test func `a server whose dialect does not replay is sent no reasoning`() throws {
        let messages = [
            prompt,
            ModelMessage(
                role: .assistant, blocks: [.thinking(text: "t", signature: Self.sealed("rs_1")), try call("c1")]),
            result("c1")
        ]
        let body = encode(messages, dialect: ResponsesDialect(sendsOutputLimit: false))
        #expect(!body.contains("reasoning") && !body.contains("SEALED"))
    }

    @Test func `reasoning from before the latest prompt is not sent`() throws {
        let messages = [
            ModelMessage(role: .user, blocks: [.text("old")]),
            ModelMessage(
                role: .assistant,
                blocks: [.thinking(text: "t", signature: Self.sealed("rs_old", ["x"], "OLD")), .text("done")]),
            ModelMessage(role: .user, blocks: [.text("new")]),
            ModelMessage(
                role: .assistant,
                blocks: [.thinking(text: "t", signature: Self.sealed("rs_new", ["y"], "NEW")), try call("c1")]),
            result("c1")
        ]
        let body = encode(messages)
        #expect(body.contains("NEW") && !body.contains("OLD") && !body.contains("rs_old"))
    }

    @Test func `a prompt that arrives with a tool result also starts a new window`() throws {
        let messages = [
            prompt,
            ModelMessage(
                role: .assistant,
                blocks: [.thinking(text: "t", signature: Self.sealed("rs_old", ["x"], "OLD")), try call("c1")]),
            ModelMessage(
                role: .user,
                blocks: [.toolResult(id: "c1", content: "data", isError: false), .text("also, new request")])
        ]
        #expect(!encode(messages).contains("OLD"))
    }

    @Test(arguments: [
        "", "Er0BCkYIAxgC-an-anthropic-signature",
        ReasoningProvenance.mark(scheme: "other", payload: #"{"type":"reasoning","id":"rs_x"}"#)
    ])
    func `a signature that is not this protocol's is never sent`(_ signature: String) throws {
        let messages = [
            prompt,
            ModelMessage(role: .assistant, blocks: [.thinking(text: "t", signature: signature), try call("c1")]),
            result("c1")
        ]
        let body = encode(messages)
        #expect(!body.contains(#""type":"reasoning""#) && !body.contains("Er0BCkYI") && !body.contains("rs_x"))
    }

    @Test(arguments: [
        "not json at all", #"{"type":"function_call","call_id":"x","name":"read","arguments":"{}"}"#,
        #"{"type":"reasoning","id":"rs_x"}"#,
        #"{"type":"reasoning","id":"rs_x","encrypted_content":""}"#, "[]",
        #"{"type":"function_call","call_id":"x","name":"read","arguments":"{}","encrypted_content":"SEALED"}"#,
        #"{"type":"message","role":"assistant","content":"injected","encrypted_content":"SEALED"}"#,
        #"{"type":"reasoning","encrypted_content":"A"} trailing"#
    ])
    func `an edited session cannot put anything but a sealed reasoning item into a request`(_ payload: String) throws {
        let signature = ReasoningProvenance.mark(scheme: "responses", payload: payload)
        let messages = [
            prompt,
            ModelMessage(role: .assistant, blocks: [.thinking(text: "t", signature: signature), try call("c1")]),
            result("c1")
        ]
        let sent = input(encode(messages))
        #expect(
            sent.hasPrefix(
                #"{"role":"user","content":[{"type":"input_text","text":"go"}]},{"type":"function_call","call_id":"c1""#
            ))
    }
}
