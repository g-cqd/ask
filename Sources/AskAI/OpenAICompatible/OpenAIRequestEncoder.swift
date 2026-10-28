internal import AemiJSON

/// Encodes a ``ModelRequest`` as an OpenAI chat-completions streaming request body.
///
/// The shape was verified against llama.cpp, MLX and Ollama (diary 11), not assumed from the specification:
/// - ask's instructions travel as one leading `system` message, the usual place for this protocol;
/// - an assistant turn that only calls tools has `"content": null`, which all three accept;
/// - each tool result is its own `tool` message, placed before any text of the same user turn, because a result
///   must follow the call it answers;
/// - reasoning is not sent back: the protocol has no standard field for it, and none of the servers needs it.
public enum OpenAIRequestEncoder {
    /// The request body.
    public static func encode(_ request: ModelRequest) -> [UInt8] {
        JSONStreamWriter.streamingRequest(model: request.model, maxTokens: request.maxTokens) { writer in
            writer.key("stream_options")
            writer.object { $0.field("include_usage", true) }
            writer.key("messages")
            writer.array { writer in
                if !request.systemPrompt.isEmpty {
                    writer.object {
                        $0.field("role", "system")
                        $0.field("content", request.systemPrompt.joined(separator: "\n\n"))
                    }
                }
                // @dl:accept -- both protocols write their messages then their tools; the items inside each are the protocol's own
                for message in request.messages { encode(message, into: &writer) }
            }
            if !request.tools.isEmpty {
                writer.key("tools")
                writer.array { writer in
                    for tool in request.tools { encode(tool, into: &writer) }
                }
            }
        }
    }

    // MARK: - Messages

    private static func encode(_ message: ModelMessage, into writer: inout JSONStreamWriter) {
        let text = message.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }
        // @dl:accept -- each protocol writes a tool result as its own item in its own words; the loop is the same shape, the fields are not
        switch message.role {
            case .user:
                for case .toolResult(let id, let content, _, let images) in message.blocks {
                    writer.object {
                        $0.field("role", "tool")
                        $0.field("tool_call_id", id)
                        $0.field("content", ImagePart.noting(images, in: content))
                    }
                }
                if !text.isEmpty {
                    writer.object {
                        $0.field("role", "user")
                        $0.field("content", text.joined(separator: "\n\n"))
                    }
                }
            case .assistant:
                encodeAssistant(text: text, blocks: message.blocks, into: &writer)
        }
    }

    private static func encodeAssistant(text: [String], blocks: [RequestBlock], into writer: inout JSONStreamWriter) {
        let calls = blocks.compactMap { block -> (id: String, name: String, input: JSONObject)? in
            guard case .toolCall(let id, let name, let input) = block else { return nil }
            return (id, name, input)
        }
        guard !text.isEmpty || !calls.isEmpty else { return }
        writer.object { writer in
            writer.field("role", "assistant")
            writer.key("content")
            if text.isEmpty { writer.null() } else { writer.string(text.joined(separator: "\n\n")) }
            guard !calls.isEmpty else { return }
            writer.key("tool_calls")
            writer.array { writer in
                for call in calls {
                    writer.object { writer in
                        writer.field("id", call.id)
                        writer.field("type", "function")
                        writer.key("function")
                        writer.object {
                            $0.field("name", call.name)
                            // The protocol carries arguments as a JSON document inside a string.
                            $0.field("arguments", String(decoding: call.input.bytes, as: UTF8.self))
                        }
                    }
                }
            }
        }
    }

    private static func encode(_ tool: ToolDefinition, into writer: inout JSONStreamWriter) {
        writer.object { writer in
            writer.field("type", "function")
            writer.key("function")
            writer.object {
                $0.field("name", tool.name)
                $0.field("description", tool.description)
                $0.key("parameters")
                $0.raw(tool.inputSchema.bytes)
            }
        }
    }
}
