/// One `data:` payload of an OpenAI-compatible chat-completions stream, as servers actually send it.
///
/// Every field is optional because the servers disagree on which they send (diary 11): llama.cpp names reasoning
/// `reasoning_content` and MLX and Ollama `reasoning`; usage arrives in a chunk, in a final `chat.completion`
/// object or in a chunk with no choices; an error replaces the whole payload. A final object's `message` is never
/// read, because it repeats what the deltas already carried.
struct OpenAIWireChunk: Decodable, Sendable {
    let id: String?
    let model: String?
    let choices: [Choice]?
    let usage: ReportedUsage?
    let error: ErrorBody?
    /// vLLM's error shape, `{"object":"error","message":…,"type":…,"code":…}`, with no `error` wrapper.
    let object: String?
    let message: String?
    let type: String?
    let code: Code?

    /// The error a payload carries at its top level, as vLLM sends it.
    var topLevelError: ErrorBody? {
        guard object == "error" else { return nil }
        return ErrorBody(message: message, type: type, code: code)
    }

    struct Choice: Decodable, Sendable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable, Sendable {
        let content: String?
        let reasoningContent: String?
        let reasoning: String?
        let toolCalls: [ToolCall]?

        /// Reasoning text under either name a server uses.
        var reasoningText: String? { reasoningContent ?? reasoning }

        enum CodingKeys: String, CodingKey {
            case content, reasoning
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable, Sendable {
        let index: Int?
        let id: String?
        let function: Function?
    }

    struct Function: Decodable, Sendable {
        let name: String?
        let arguments: String?
    }

    struct ErrorBody: Decodable, Sendable {
        let message: String?
        let type: String?
        let code: Code?
        /// llama.cpp's context size, sent with a refusal for length.
        var nCtx: Int?

        enum CodingKeys: String, CodingKey {
            case message, type, code
            case nCtx = "n_ctx"
        }
    }

    /// An error `code`, which servers send as a number or as a string.
    enum Code: Decodable, Sendable {
        case number(Int)
        case text(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                self = .number(number)
            } else {
                self = .text(try container.decode(String.self))
            }
        }
    }
}
