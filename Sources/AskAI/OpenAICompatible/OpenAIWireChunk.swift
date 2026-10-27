/// One `data:` payload of an OpenAI-compatible chat-completions stream, as servers actually send it.
///
/// Every field is optional because the servers disagree on which they send (diary 11): llama.cpp names reasoning
/// `reasoning_content` and MLX and Ollama `reasoning`; usage arrives in a chunk, in a final `chat.completion`
/// object or in a chunk with no choices; an error replaces the whole payload. A final object's `message` is never
/// read, because it repeats what the deltas already carried. A delta's `content` is a plain string on most servers
/// but a list of parts on Mistral's reasoning models (diary 22); ``Content`` reads either.
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
        return ErrorBody(message: message, type: type, code: code, resetsIn: nil)
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
        let content: Content?
        let reasoningContent: String?
        let reasoning: String?
        let toolCalls: [ToolCall]?

        /// The visible text this delta carries, whether the server sent a plain string or content parts.
        var text: String? { content?.text }
        /// Reasoning text under any name a server uses: `reasoning_content`, `reasoning`, or a thinking part.
        var reasoningText: String? { reasoningContent ?? reasoning ?? content?.reasoning }

        enum CodingKeys: String, CodingKey {
            case content, reasoning
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }

    /// A delta's `content`: a plain string on most servers, but Mistral's reasoning models send a list of parts
    /// instead — `{"type":"text","text":…}` for text and `{"type":"thinking","thinking":[{"type":"text","text":…}],"closed":…}`
    /// for reasoning (probed live against api.mistral.ai, `zai-glm-5-3` and `mistral-large-4`, diary 22; `closed`
    /// is present on some thinking parts and absent on others, and one part can carry several segments). Both shapes
    /// are read, so one decoder serves every server.
    enum Content: Decodable, Sendable {
        case string(String)
        case parts([Part])

        /// The text this content carries: the string itself, or the joined `text` parts.
        var text: String? {
            switch self {
                case .string(let text): return text
                case .parts(let parts):
                    let joined = parts.compactMap { $0.type == "text" ? $0.text : nil }.joined()
                    return joined.isEmpty ? nil : joined
            }
        }

        /// The reasoning this content carries, joined from its `thinking` parts.
        var reasoning: String? {
            guard case .parts(let parts) = self else { return nil }
            let joined = parts.compactMap { $0.type == "thinking" ? $0.reasoning : nil }.joined()
            return joined.isEmpty ? nil : joined
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .parts(try container.decode([Part].self))
            }
        }

        /// One part of a content list: a `text` part or a `thinking` part. A part of any other type carries
        /// nothing this decoder reads, and is ignored like any other unknown field.
        struct Part: Decodable, Sendable {
            let type: String?
            let text: String?
            let thinking: [Segment]?

            /// The reasoning this part carries, joined from its thinking segments.
            var reasoning: String? {
                guard let thinking else { return nil }
                let joined = thinking.compactMap(\.text).joined()
                return joined.isEmpty ? nil : joined
            }

            /// One thinking segment, `{"type":"text","text":…}`.
            struct Segment: Decodable, Sendable {
                let text: String?
            }
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
        /// Seconds until a usage limit lifts, which ChatGPT's backend sends (`resets_in_seconds`).
        let resetsIn: Lenient<Int>?

        enum CodingKeys: String, CodingKey {
            case message, type, code
            case nCtx = "n_ctx"
            case resetsIn = "resets_in_seconds"
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
