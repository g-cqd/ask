import Testing

@testable import AskAI

/// Anthropic Messages request bodies, in the shape subscription inference accepts (ADR-0007): the system
/// parameter is exactly the canonical identity line, and ask's own prompt rides at the front of the first
/// user message, after any tool results.
@Suite("Anthropic requests carry the system prompt in user messages")
struct AnthropicRequestTests {
    private func body(_ request: ModelRequest) -> String {
        // Shape tests turn caching off; the caching tests below pin where breakpoints go.
        String(decoding: AnthropicRequestEncoder.encode(request, caching: false), as: UTF8.self)
    }

    private func request(_ messages: [ModelMessage], prompt: [String] = ["Be brief."], tools: [ToolDefinition] = [])
        -> ModelRequest
    {
        ModelRequest(model: "claude-x", maxTokens: 1024, systemPrompt: prompt, messages: messages, tools: tools)
    }

    private let head =
        #"{"model":"claude-x","max_tokens":1024,"stream":true,"#
        + #""system":[{"type":"text","text":"You are a Claude agent, built on Anthropic's Claude Agent SDK."}],"#

    @Test func `the prompt leads the first user message`() {
        let encoded = body(request([ModelMessage(role: .user, blocks: [.text("Hi")])]))
        #expect(
            encoded == head + #""messages":[{"role":"user","content":["#
                + #"{"type":"text","text":"Be brief."},{"type":"text","text":"Hi"}]}]}"#)
    }

    @Test func `the prompt follows the tool results that must lead a user message`() {
        let encoded = body(
            request([
                ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "42", isError: false), .text("and?")])
            ]))
        #expect(
            encoded == head + #""messages":[{"role":"user","content":["#
                + #"{"type":"tool_result","tool_use_id":"t1","content":"42"},"#
                + #"{"type":"text","text":"Be brief."},{"type":"text","text":"and?"}]}]}"#)
    }

    @Test func `without a leading user message, one is added to carry the prompt`() {
        #expect(
            body(request([])) == head + #""messages":[{"role":"user","content":[{"type":"text","text":"Be brief."}]}]}"#
        )
        let encoded = body(request([ModelMessage(role: .assistant, blocks: [.text("Hello")])]))
        #expect(
            encoded == head + #""messages":[{"role":"user","content":[{"type":"text","text":"Be brief."}]},"#
                + #"{"role":"assistant","content":[{"type":"text","text":"Hello"}]}]}"#)
    }

    @Test func `no prompt adds nothing`() {
        let encoded = body(request([ModelMessage(role: .user, blocks: [.text("Hi")])], prompt: []))
        #expect(encoded == head + #""messages":[{"role":"user","content":[{"type":"text","text":"Hi"}]}]}"#)
        let resumed = body(request([ModelMessage(role: .assistant, blocks: [.text("Hello")])], prompt: []))
        #expect(resumed == head + #""messages":[{"role":"assistant","content":[{"type":"text","text":"Hello"}]}]}"#)
    }

    @Test func `assistant blocks replay exactly, tool input spliced verbatim`() throws {
        let input = try JSONObject(validating: Array(#"{"path": "a.swift"}"#.utf8))
        let encoded = body(
            request(
                [
                    ModelMessage(role: .user, blocks: [.text("Go")]),
                    ModelMessage(
                        role: .assistant,
                        blocks: [
                            .thinking(text: "Hmm", signature: "sig=="), .redactedThinking(data: "opaque"),
                            .text("Reading."),
                            .toolCall(id: "toolu_1", name: "read", input: input)
                        ]),
                    ModelMessage(
                        role: .user, blocks: [.toolResult(id: "toolu_1", content: "no such file", isError: true)])
                ], prompt: []))
        #expect(
            encoded == head + #""messages":[{"role":"user","content":[{"type":"text","text":"Go"}]},"#
                + #"{"role":"assistant","content":[{"type":"thinking","thinking":"Hmm","signature":"sig=="},"#
                + #"{"type":"redacted_thinking","data":"opaque"},{"type":"text","text":"Reading."},"#
                + #"{"type":"tool_use","id":"toolu_1","name":"read","input":{"path": "a.swift"}}]},"#
                + #"{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"no such file","#
                + #""is_error":true}]}]}"#)
    }

    @Test func `reasoning another provider produced, with no signature, is not sent to Anthropic`() {
        // A session that began on an OpenAI-compatible server holds thinking blocks with no signature. Anthropic
        // rejects a thinking block whose signature it did not issue, so a resumed session would fail every turn.
        let messages = [
            ModelMessage(role: .user, blocks: [.text("Q")]),
            ModelMessage(role: .assistant, blocks: [.thinking(text: "local", signature: ""), .text("A")]),
            ModelMessage(role: .assistant, blocks: [.thinking(text: "only", signature: "")]),
            ModelMessage(role: .user, blocks: [.text("Again")])
        ]
        let encoded = body(request(messages, prompt: []))
        #expect(!encoded.contains("local"))
        #expect(!encoded.contains("only"))
        #expect(encoded.contains(#"{"role":"assistant","content":[{"type":"text","text":"A"}]}"#))
        // A message left with nothing is dropped, never sent with empty content, which the API refuses.
        #expect(!encoded.contains(#""content":[]"#))
    }

    @Test func `signed reasoning is still sent back exactly`() {
        let messages = [ModelMessage(role: .assistant, blocks: [.thinking(text: "t", signature: "sig"), .text("A")])]
        #expect(body(request(messages, prompt: [])).contains(#"{"type":"thinking","thinking":"t","signature":"sig"}"#))
    }

    @Test func `tools are declared with their schema, and omitted when there are none`() throws {
        let schema = try JSONObject(validating: Array(#"{"type":"object"}"#.utf8))
        let tool = ToolDefinition(name: "read", description: "Read a file.", inputSchema: schema)
        let encoded = body(request([ModelMessage(role: .user, blocks: [.text("Hi")])], prompt: [], tools: [tool]))
        #expect(
            encoded.hasSuffix(
                #"}]}],"tools":[{"name":"read","description":"Read a file.","input_schema":{"type":"object"}}]}"#))
    }

    @Test func `text is escaped, and non-ASCII is kept as UTF-8`() {
        let encoded = body(request([ModelMessage(role: .user, blocks: [.text("a \"quote\"\n\tand é/本")])], prompt: []))
        #expect(encoded.contains(#""text":"a \"quote\"\n\tand é/本""#))
    }

    // MARK: - Prompt caching

    private func cached(_ request: ModelRequest) -> String {
        String(decoding: AnthropicRequestEncoder.encode(request), as: UTF8.self)
    }

    private let mark = #","cache_control":{"type":"ephemeral"}"#

    @Test func `caching marks the end of the prompt, the last tool, and the end of the conversation`() throws {
        let schema = try JSONObject(validating: Array(#"{"type":"object"}"#.utf8))
        let tool = ToolDefinition(name: "read", description: "Read.", inputSchema: schema)
        let encoded = cached(
            request(
                [
                    ModelMessage(role: .user, blocks: [.text("Hi")]),
                    ModelMessage(role: .assistant, blocks: [.text("Hello")]),
                    ModelMessage(role: .user, blocks: [.text("Again")])
                ], prompt: ["One.", "Two."], tools: [tool]))
        #expect(encoded.contains(#"{"type":"text","text":"One."},{"type":"text","text":"Two.""# + mark + "}"))
        #expect(encoded.contains(#"{"type":"text","text":"Again""# + mark + "}"))
        #expect(encoded.contains(#""input_schema":{"type":"object"}"# + mark + "}"))
        #expect(encoded.ranges(of: "cache_control").count == 3, "three breakpoints, within the four allowed")
        #expect(!encoded.contains(#""text":"Hi""# + mark))
    }

    @Test func `the conversation breakpoint skips blocks that cannot carry one`() {
        let encoded = cached(
            request(
                [ModelMessage(role: .assistant, blocks: [.text("Answer"), .thinking(text: "t", signature: "s")])],
                prompt: []))
        #expect(encoded.contains(#"{"type":"text","text":"Answer""# + mark + "}"))
        #expect(!encoded.contains(#""signature":"s""# + mark))
    }

    @Test func `when the prompt is the last block, it carries one breakpoint, not two`() {
        let encoded = cached(request([], prompt: ["Only."]))
        #expect(encoded.ranges(of: "cache_control").count == 1)
    }

    @Test func `tool results carry the conversation breakpoint`() {
        let encoded = cached(
            request(
                [ModelMessage(role: .user, blocks: [.toolResult(id: "t", content: "42", isError: false)])], prompt: []))
        #expect(encoded.contains(#""content":"42""# + mark + "}"))
    }

    @Test func `only a JSON object is accepted as tool input or schema`() {
        for bytes in ["[1]", "42", "\"s\"", #"{"open": "#, ""] {
            #expect(throws: JSONObject.Invalid.self) { _ = try JSONObject(validating: Array(bytes.utf8)) }
        }
    }
}
