internal import Foundation
internal import Testing

@testable import AskAI

/// What ask sends to an OpenAI-compatible server, byte for byte.
///
/// The shape was checked against llama.cpp, MLX and Ollama before it was written down (diary 11): each accepted an
/// assistant turn with `"content": null` and `tool_calls`, a `tool` message per result, and `stream_options`.
@Suite("Requests are encoded as OpenAI chat completions")
struct OpenAIRequestEncoderTests {
    private static let schema = try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8))

    private func encode(_ request: ModelRequest) -> String {
        String(decoding: OpenAIRequestEncoder.encode(request), as: UTF8.self)
    }

    @Test func `a conversation with a tool round trip`() throws {
        let request = ModelRequest(
            model: "m", maxTokens: 100, systemPrompt: ["Be brief.", "Use tools."],
            messages: [
                ModelMessage(role: .user, blocks: [.text("hi")]),
                ModelMessage(
                    role: .assistant,
                    blocks: [
                        .thinking(text: "private", signature: ""), .text("Reading."),
                        .toolCall(
                            id: "c1", name: "read", input: try JSONObject(validating: Array(#"{"path":"x"}"#.utf8)))
                    ]),
                ModelMessage(
                    role: .user, blocks: [.toolResult(id: "c1", content: "data", isError: false), .text("next")])
            ],
            tools: [ToolDefinition(name: "read", description: "Read.", inputSchema: Self.schema)])
        #expect(
            encode(request)
                == #"{"model":"m","max_tokens":100,"stream":true,"stream_options":{"include_usage":true},"messages":["#
                + #"{"role":"system","content":"Be brief.\n\nUse tools."},{"role":"user","content":"hi"},"#
                + #"{"role":"assistant","content":"Reading.","tool_calls":[{"id":"c1","type":"function","function":"#
                + #"{"name":"read","arguments":"{\"path\":\"x\"}"}}]},"#
                + #"{"role":"tool","tool_call_id":"c1","content":"data"},{"role":"user","content":"next"}],"#
                + #""tools":[{"type":"function","function":{"name":"read","description":"Read.","parameters":{"type":"object"}}}]}"#
        )
    }

    @Test func `a turn that only calls tools sends null content, as every server checked accepts`() throws {
        let request = ModelRequest(
            model: "m", maxTokens: 1, systemPrompt: [],
            messages: [ModelMessage(role: .assistant, blocks: [.toolCall(id: "c", name: "t", input: .empty)])],
            tools: [])
        #expect(
            encode(request)
                == #"{"model":"m","max_tokens":1,"stream":true,"stream_options":{"include_usage":true},"messages":["#
                + #"{"role":"assistant","content":null,"tool_calls":[{"id":"c","type":"function","function":"#
                + #"{"name":"t","arguments":"{}"}}]}]}"#)
    }

    @Test func `no system prompt and no tools leave both out`() {
        let request = ModelRequest(
            model: "m", maxTokens: 5, systemPrompt: [], messages: [ModelMessage(role: .user, blocks: [.text("x")])],
            tools: [])
        #expect(!encode(request).contains("system"))
        #expect(!encode(request).contains("tools"))
    }

    @Test func `reasoning and redacted reasoning are never sent back`() {
        let request = ModelRequest(
            model: "m", maxTokens: 5, systemPrompt: [],
            messages: [
                ModelMessage(
                    role: .assistant,
                    blocks: [.thinking(text: "secret", signature: "s"), .redactedThinking(data: "r"), .text("done")])
            ],
            tools: [])
        let body = encode(request)
        #expect(!body.contains("secret"))
        #expect(!body.contains("\"r\""))
        #expect(body.contains(#""content":"done""#))
    }

    @Test func `text and results that need escaping produce valid JSON`() throws {
        let request = ModelRequest(
            model: "m", maxTokens: 5, systemPrompt: ["quote \" and\nnewline"],
            messages: [ModelMessage(role: .user, blocks: [.toolResult(id: "c", content: "tab\tand ✓", isError: true)])],
            tools: [])
        let parsed = try JSONSerialization.jsonObject(with: Data(OpenAIRequestEncoder.encode(request)))
        let messages = try #require((parsed as? [String: Any])?["messages"] as? [[String: Any]])
        #expect(messages.first?["content"] as? String == "quote \" and\nnewline")
        #expect(messages.last?["content"] as? String == "tab\tand ✓")
    }
}
