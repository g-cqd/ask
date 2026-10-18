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
        writer.beginObject()
        writer.key("model")
        writer.string(request.model)
        writer.key("max_tokens")
        writer.integer(request.maxTokens)
        writer.key("stream")
        writer.bool(true)
        writer.key("system")
        writer.beginArray()
        text(canonicalSystemLine, into: &writer)
        writer.endArray()
        writer.key("messages")
        writer.beginArray()
        for message in carryingPrompt(request.systemPrompt, in: request.messages) {
            encode(message, into: &writer)
        }
        writer.endArray()
        if !request.tools.isEmpty {
            writer.key("tools")
            writer.beginArray()
            for tool in request.tools { encode(tool, into: &writer) }
            writer.endArray()
        }
        writer.endObject()
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
        writer.beginObject()
        writer.key("role")
        writer.string(message.role == .user ? "user" : "assistant")
        writer.key("content")
        writer.beginArray()
        for block in message.blocks { encode(block, into: &writer) }
        writer.endArray()
        writer.endObject()
    }

    private static func encode(_ block: RequestBlock, into writer: inout JSONStreamWriter) {
        switch block {
            case .text(let value): text(value, into: &writer)
            case .thinking(let thinking, let signature):
                writer.beginObject()
                field("type", "thinking", into: &writer)
                field("thinking", thinking, into: &writer)
                field("signature", signature, into: &writer)
                writer.endObject()
            case .redactedThinking(let data):
                writer.beginObject()
                field("type", "redacted_thinking", into: &writer)
                field("data", data, into: &writer)
                writer.endObject()
            case .toolCall(let id, let name, let input):
                writer.beginObject()
                field("type", "tool_use", into: &writer)
                field("id", id, into: &writer)
                field("name", name, into: &writer)
                writer.key("input")
                writer.raw(input.bytes)
                writer.endObject()
            case .toolResult(let id, let content, let isError):
                writer.beginObject()
                field("type", "tool_result", into: &writer)
                field("tool_use_id", id, into: &writer)
                field("content", content, into: &writer)
                if isError {
                    writer.key("is_error")
                    writer.bool(true)
                }
                writer.endObject()
        }
    }

    private static func encode(_ tool: ToolDefinition, into writer: inout JSONStreamWriter) {
        writer.beginObject()
        field("name", tool.name, into: &writer)
        field("description", tool.description, into: &writer)
        writer.key("input_schema")
        writer.raw(tool.inputSchema.bytes)
        writer.endObject()
    }

    private static func text(_ value: String, into writer: inout JSONStreamWriter) {
        writer.beginObject()
        field("type", "text", into: &writer)
        field("text", value, into: &writer)
        writer.endObject()
    }

    private static func field(_ key: String, _ value: String, into writer: inout JSONStreamWriter) {
        writer.key(key)
        writer.string(value)
    }
}
