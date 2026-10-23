internal import AemiJSON

/// Encodes a ``ModelRequest`` as a Responses API streaming request body.
///
/// The conversation is a flat list of items rather than messages:
/// - ask's instructions travel as `instructions`, not as a leading message;
/// - a user turn is `input_text`; each tool result is its own `function_call_output` item, placed before any text of
///   the same turn, because a result must follow the call it answers;
/// - an assistant turn is its text, and each tool call its own `function_call` item, in the order the model wrote
///   them; a call and its result are matched by `call_id`;
/// - a call carries no item `id`. Reasoning the server sealed is sent back verbatim, with its own id, in order before the
///   call it preceded, only for a dialect that replays it and only within the tool loop in progress (ADR-0061);
/// - `store` is false: ask keeps the conversation, the server need not.
public enum ResponsesRequestEncoder {
    /// The request body.
    /// - Parameters:
    ///   - request: what to ask.
    ///   - dialect: how this server differs from the plain API.
    /// - Returns: the JSON body.
    public static func encode(_ request: ModelRequest, dialect: ResponsesDialect = .standard) -> [UInt8] {
        JSONStreamWriter.streamingRequest(
            model: request.model, maxTokens: request.maxTokens,
            limitField: dialect.sendsOutputLimit ? "max_output_tokens" : nil
        ) { writer in
            writer.field("store", false)
            encodeThinking(request.thinking, into: &writer)
            let instructions =
                request.systemPrompt.isEmpty
                ? dialect.fallbackInstructions : request.systemPrompt.joined(separator: "\n\n")
            if let instructions { writer.field("instructions", instructions) }
            writer.key("input")
            let window = dialect.replaysReasoning ? promptIndex(request.messages) + 1 : Int.max
            writer.array { writer in
                for (index, message) in request.messages.enumerated() {
                    encode(message, replaying: index >= window, into: &writer)
                }
            }
            if !request.tools.isEmpty {
                writer.key("tools")
                writer.array { writer in
                    for tool in request.tools { encode(tool, into: &writer) }
                }
                writer.field("tool_choice", "auto")
                writer.field("parallel_tool_calls", true)
            }
            if let key = dialect.promptCacheKey { writer.field("prompt_cache_key", key) }
        }
    }

    // MARK: - Items

    private static func encode(_ message: ModelMessage, replaying: Bool, into writer: inout JSONStreamWriter) {
        switch message.role {
            case .user:
                for case .toolResult(let id, let content, _) in message.blocks {
                    writer.object {
                        $0.field("type", "function_call_output")
                        $0.field("call_id", id)
                        $0.field("output", content)
                    }
                }
                let text = message.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }
                if !text.isEmpty {
                    writer.object { writer in
                        writer.field("role", "user")
                        writer.key("content")
                        writer.array { $0.typed("input_text", "text", text.joined(separator: "\n\n")) }
                    }
                }
            case .assistant: encodeAssistant(message.blocks, replaying: replaying, into: &writer)
        }
    }

    /// Text and calls in the order the model produced them; a run of text blocks is one item.
    private static func encodeAssistant(_ blocks: [RequestBlock], replaying: Bool, into writer: inout JSONStreamWriter)
    {
        var run: [String] = []
        func flush(_ writer: inout JSONStreamWriter) {
            guard !run.isEmpty else { return }
            let text = run.joined(separator: "\n\n")
            writer.object {
                $0.field("role", "assistant")
                $0.field("content", text)
            }
            run.removeAll()
        }
        for block in blocks {
            switch block {
                case .text(let text): run.append(text)
                case .toolCall(let id, let name, let input):
                    flush(&writer)
                    writer.object {
                        $0.field("type", "function_call")
                        $0.field("call_id", id)
                        $0.field("name", name)
                        // The protocol carries arguments as a JSON document inside a string.
                        $0.field("arguments", String(decoding: input.bytes, as: UTF8.self))
                    }
                case .thinking(_, let signature):
                    if replaying, let item = replayable(signature) {
                        flush(&writer)
                        writer.raw(item)
                    }
                case .redactedThinking, .toolResult: break
            }
        }
        flush(&writer)
    }

    private static func encode(_ tool: ToolDefinition, into writer: inout JSONStreamWriter) {
        writer.object { writer in
            writer.field("type", "function")
            writer.field("name", tool.name)
            writer.field("description", tool.description)
            writer.key("parameters")
            writer.raw(tool.inputSchema.bytes)
            writer.field("strict", false)
        }
    }
}
