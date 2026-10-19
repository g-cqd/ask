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
public enum AnthropicRequestEncoder {
    /// The first-party identity line the subscription gate requires as the whole `system` parameter.
    public static let canonicalSystemLine = "You are a Claude agent, built on Anthropic's Claude Agent SDK."

    /// The request body.
    public static func encode(_ request: ModelRequest) -> [UInt8] {
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
                for message in carryingPrompt(request.systemPrompt, in: request.messages) {
                    encode(message, into: &writer)
                }
            }
            if !request.tools.isEmpty {
                writer.key("tools")
                writer.array { writer in
                    for tool in request.tools { encode(tool, into: &writer) }
                }
            }
        }
        return writer.finish()
    }

    /// The messages with the prompt moved into the first user message.
    static func carryingPrompt(_ prompt: [String], in messages: [ModelMessage]) -> [ModelMessage] {
        guard !prompt.isEmpty else { return messages }
        let promptBlocks = prompt.map(RequestBlock.text)
        guard var first = messages.first, first.role == .user else {
            return [ModelMessage(role: .user, blocks: promptBlocks)] + messages
        }
        var lead = 0
        while lead < first.blocks.count, case .toolResult = first.blocks[lead] { lead += 1 }
        first.blocks.insert(contentsOf: promptBlocks, at: lead)
        return [first] + messages.dropFirst()
    }

    // MARK: - Pieces

    private static func encode(_ message: ModelMessage, into writer: inout JSONStreamWriter) {
        writer.object { writer in
            writer.field("role", message.role == .user ? "user" : "assistant")
            writer.key("content")
            writer.array { writer in
                for block in message.blocks { encode(block, into: &writer) }
            }
        }
    }

    private static func encode(_ block: RequestBlock, into writer: inout JSONStreamWriter) {
        switch block {
            case .text(let value): writer.typed("text", "text", value)
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
                }
        }
    }

    private static func encode(_ tool: ToolDefinition, into writer: inout JSONStreamWriter) {
        writer.object {
            $0.field("name", tool.name)
            $0.field("description", tool.description)
            $0.key("input_schema")
            $0.raw(tool.inputSchema.bytes)
        }
    }
}
