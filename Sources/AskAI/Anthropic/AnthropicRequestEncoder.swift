internal import AemiJSON

/// Encodes a ``ModelRequest`` as an Anthropic Messages streaming request body.
///
/// Always in the shape subscription inference accepts (ADR-0007). The `system` parameter is exactly the
/// canonical identity line. ask's prompt rides as text blocks at the front of the first user message, after
/// any `tool_result` blocks, which the API requires to lead. A user message is added when none leads the
/// conversation. API-key requests accept the same shape, so there is one path, not two.
///
/// Written with a streaming writer straight into one buffer; tool input and schemas are spliced verbatim,
/// because ``JSONObject`` validated them when they were made.
///
/// **Prompt caching.** Three `cache_control` breakpoints, within the four the API allows:
/// - the last tool, which caches the tools and the system line;
/// - the last prompt block, which caches ask's instructions;
/// - the last block of the conversation that can carry one, so the next turn reads everything before it
///   from cache.
///
/// The history is re-sent every turn; without these, every turn paid full input price for all of it.
public enum AnthropicRequestEncoder {
    /// The first-party identity line the subscription gate requires as the whole `system` parameter.
    public static let canonicalSystemLine = "You are a Claude agent, built on Anthropic's Claude Agent SDK."

    /// The request body.
    /// - Parameters:
    ///   - request: the request to encode.
    ///   - caching: whether to place prompt-caching breakpoints. On for every real request; shape tests turn
    ///     it off to keep their expectations readable.
    /// - Returns: the JSON body.
    public static func encode(_ request: ModelRequest, caching: Bool = true) -> [UInt8] {
        let (messages, promptEnd) = carryingPromptMarkingItsEnd(request.systemPrompt, in: request.messages)
        let marks = caching ? [promptEnd, conversationEnd(messages)].compactMap { $0 } : []
        var writer = JSONStreamWriter(capacity: 4_096)
        writer.object { writer in
            writer.field("model", request.model)
            writer.field("max_tokens", request.maxTokens)
            writer.key("stream")
            writer.bool(true)
            writer.key("system")
            writer.array { $0.typed("text", "text", canonicalSystemLine) }
            writer.key("messages")
            writer.array { writer in
                for (index, message) in messages.enumerated() {
                    encode(message, into: &writer, marking: marks.filter { $0.message == index }.map(\.block))
                }
            }
            if !request.tools.isEmpty {
                writer.key("tools")
                writer.array { writer in
                    for (index, tool) in request.tools.enumerated() {
                        encode(tool, into: &writer, cached: caching && index == request.tools.count - 1)
                    }
                }
            }
        }
        return writer.finish()
    }

    /// The messages with the prompt moved in, and where its last block landed.
    private static func carryingPromptMarkingItsEnd(
        _ prompt: [String], in messages: [ModelMessage]
    ) -> (messages: [ModelMessage], promptEnd: (message: Int, block: Int)?) {
        guard !prompt.isEmpty else { return (messages, nil) }
        let promptBlocks = prompt.map(RequestBlock.text)
        guard var first = messages.first, first.role == .user else {
            return ([ModelMessage(role: .user, blocks: promptBlocks)] + messages, (0, promptBlocks.count - 1))
        }
        var lead = 0
        while lead < first.blocks.count, case .toolResult = first.blocks[lead] { lead += 1 }
        first.blocks.insert(contentsOf: promptBlocks, at: lead)
        return ([first] + messages.dropFirst(), (0, lead + promptBlocks.count - 1))
    }

    /// The last block of the conversation that can carry a breakpoint: thinking blocks cannot.
    private static func conversationEnd(_ messages: [ModelMessage]) -> (message: Int, block: Int)? {
        guard let last = messages.indices.last else { return nil }
        let block = messages[last].blocks
            .lastIndex { block in
                switch block {
                    case .thinking, .redactedThinking: false
                    default: true
                }
            }
        return block.map { (last, $0) }
    }

    // MARK: - Pieces

    private static func encode(_ message: ModelMessage, into writer: inout JSONStreamWriter, marking marked: [Int]) {
        writer.object { writer in
            writer.field("role", message.role == .user ? "user" : "assistant")
            writer.key("content")
            writer.array { writer in
                for (index, block) in message.blocks.enumerated() {
                    encode(block, into: &writer, cached: marked.contains(index))
                }
            }
        }
    }

    /// Writes the breakpoint member, inside the object being written, when `cached`.
    private static func breakpoint(if cached: Bool, _ writer: inout JSONStreamWriter) {
        guard cached else { return }
        writer.key("cache_control")
        writer.object { $0.field("type", "ephemeral") }
    }

    private static func encode(_ block: RequestBlock, into writer: inout JSONStreamWriter, cached: Bool) {
        switch block {
            case .text(let value):
                writer.object {
                    $0.field("type", "text")
                    $0.field("text", value)
                    breakpoint(if: cached, &$0)
                }
            case .thinking(let thinking, let signature):
                writer.object {
                    $0.field("type", "thinking")
                    $0.field("thinking", thinking)
                    $0.field("signature", signature)
                }
            case .redactedThinking(let data): writer.typed("redacted_thinking", "data", data)
            // @dl:accept -- tool_use and tool_result are two wire shapes that happen to share a field count; they read best written out
            case .toolCall(let id, let name, let input):
                writer.object {
                    $0.field("type", "tool_use")
                    $0.field("id", id)
                    $0.field("name", name)
                    $0.key("input")
                    $0.raw(input.bytes)
                    breakpoint(if: cached, &$0)
                }
            case .toolResult(let id, let content, let isError):
                writer.object {
                    $0.field("type", "tool_result")
                    $0.field("tool_use_id", id)
                    $0.field("content", content)
                    if isError {
                        $0.key("is_error")
                        $0.bool(true)
                    }
                    breakpoint(if: cached, &$0)
                }
        }
    }

    private static func encode(_ tool: ToolDefinition, into writer: inout JSONStreamWriter, cached: Bool) {
        writer.object {
            $0.field("name", tool.name)
            $0.field("description", tool.description)
            $0.key("input_schema")
            $0.raw(tool.inputSchema.bytes)
            breakpoint(if: cached, &$0)
        }
    }
}
