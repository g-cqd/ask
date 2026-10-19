internal import Foundation
internal import Testing

@testable import AskAI

/// What ask sends to a Responses server, byte for byte.
///
/// Items, not messages: a user turn is `input_text`, an assistant turn is plain text, a call is a `function_call` and
/// its result a `function_call_output`, both keyed by `call_id`. Reasoning is not sent back yet (ADR-0033), and nothing
/// carries an item `id`, so OpenAI has no pairing to check. llama.cpp accepted this shape (diary 22); OpenAI has not
/// been tried.
@Suite("Requests are encoded as Responses API items")
struct ResponsesRequestEncoderTests {
    private static let schema = try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8))
    private static let tool = ToolDefinition(name: "read", description: "Read.", inputSchema: schema)

    private func encode(_ request: ModelRequest, dialect: ResponsesDialect = .standard) -> String {
        String(decoding: ResponsesRequestEncoder.encode(request, dialect: dialect), as: UTF8.self)
    }

    private func call(_ id: String, _ json: String) throws -> RequestBlock {
        .toolCall(id: id, name: "read", input: try JSONObject(validating: Array(json.utf8)))
    }

    @Test func `a conversation with a tool round trip`() throws {
        let request = ModelRequest(
            model: "m", maxTokens: 100, systemPrompt: ["Be brief.", "Use tools."],
            messages: [
                ModelMessage(role: .user, blocks: [.text("hi")]),
                ModelMessage(
                    role: .assistant,
                    blocks: [
                        .thinking(text: "private", signature: ""), .text("Reading."), try call("c1", #"{"path":"x"}"#)
                    ]),
                ModelMessage(
                    role: .user, blocks: [.toolResult(id: "c1", content: "data", isError: false), .text("next")])
            ], tools: [Self.tool])
        #expect(
            encode(request)
                == #"{"model":"m","max_output_tokens":100,"stream":true,"store":false,"instructions":"Be brief.\n\nUse tools.","#
                + #""input":[{"role":"user","content":[{"type":"input_text","text":"hi"}]},"#
                + #"{"role":"assistant","content":"Reading."},"#
                + #"{"type":"function_call","call_id":"c1","name":"read","arguments":"{\"path\":\"x\"}"},"#
                + #"{"type":"function_call_output","call_id":"c1","output":"data"},"#
                + #"{"role":"user","content":[{"type":"input_text","text":"next"}]}],"#
                + #""tools":[{"type":"function","name":"read","description":"Read.","parameters":{"type":"object"},"strict":false}],"#
                + #""tool_choice":"auto","parallel_tool_calls":true}"#)
    }

    @Test func `a server that rejects an output limit is sent none`() {
        let request = ModelRequest(
            model: "m", maxTokens: 100, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])
        #expect(!encode(request, dialect: ResponsesDialect(sendsOutputLimit: false)).contains("max_output_tokens"))
        #expect(encode(request).contains(#""max_output_tokens":100"#))
    }

    @Test func `no instructions and no tools leave those fields out`() {
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])
        let body = encode(request)
        #expect(!body.contains("instructions"))
        #expect(!body.contains("tools"))
        #expect(!body.contains("tool_choice"))
    }

    @Test func `text around a call keeps its order, as separate items`() throws {
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [
                ModelMessage(
                    role: .assistant,
                    blocks: [.text("before"), .text("more"), try call("c", "{}"), .text("after")])
            ], tools: [])
        #expect(
            encode(request)
                .contains(
                    #""input":[{"role":"assistant","content":"before\n\nmore"},"#
                        + #"{"type":"function_call","call_id":"c","name":"read","arguments":"{}"},"#
                        + #"{"role":"assistant","content":"after"}]"#))
    }

    @Test func `reasoning of every origin stays at home, and a turn left empty is not sent`() {
        let sealed = ReasoningProvenance.mark(scheme: "responses", payload: #"{"id":"rs_1"}"#)
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [
                ModelMessage(role: .user, blocks: [.text("hi")]),
                ModelMessage(
                    role: .assistant,
                    blocks: [
                        .thinking(text: "sealed", signature: sealed),
                        .thinking(text: "anthropic's", signature: "EqQB=="),
                        .redactedThinking(data: "opaque")
                    ]),
                ModelMessage(role: .assistant, blocks: [.text("ok")])
            ], tools: [])
        let body = encode(request)
        #expect(!body.contains("sealed"))
        #expect(!body.contains("EqQB"))
        #expect(!body.contains("opaque"))
        #expect(!body.contains("reasoning"))
        #expect(body.contains(#"{"role":"assistant","content":"ok"}"#))
    }

    @Test func `a result with no text beside it is a bare output item`() {
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.toolResult(id: "c", content: "boom", isError: true)])],
            tools: [])
        #expect(encode(request).contains(#""input":[{"type":"function_call_output","call_id":"c","output":"boom"}]"#))
    }

    @Test func `a cache key is sent last, and only when the dialect has one`() {
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])
        #expect(
            encode(request, dialect: ResponsesDialect(promptCacheKey: "sess-1"))
                .hasSuffix(#","prompt_cache_key":"sess-1"}"#))
        #expect(!encode(request).contains("prompt_cache_key"))
    }

    @Test func `instructions the server insists on are supplied only when ask has none`() {
        let bare = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])
        let dialect = ResponsesDialect(fallbackInstructions: "You are a helpful assistant.")
        #expect(encode(bare, dialect: dialect).contains(#""instructions":"You are a helpful assistant.""#))
        var given = bare
        given.systemPrompt = ["Mine."]
        let body = encode(given, dialect: dialect)
        #expect(body.contains(#""instructions":"Mine.""#))
        #expect(!body.contains("helpful assistant"))
    }
}
