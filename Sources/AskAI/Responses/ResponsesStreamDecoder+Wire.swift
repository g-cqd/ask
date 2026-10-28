internal import AemiJSON

extension ResponsesStreamDecoder {
    /// Events that carry nothing ask needs: progress, part boundaries, and the `done` echoes of text already streamed.
    // @dl:accept -- a set of event names is data, like the model-id lists in the tests
    static let quiet: Set<String> = [
        "response.created", "response.in_progress", "response.queued", "response.content_part.added",
        "response.content_part.done", "response.output_text.done", "response.refusal.done",
        "response.reasoning_text.done", "response.reasoning_summary_text.done", "response.reasoning_summary_part.done",
        "response.function_call_arguments.done", "response.output_text.annotation.added",
        "keepalive"
    ]

    /// Why the response stopped. A reply cut at the output limit is `incomplete` on OpenAI and, measured, `completed` on
    /// llama.cpp; the loop does not depend on telling them apart (ADR-0030).
    static func stopReason(of response: ResponsesWireEvent.Response, called: Bool, refused: Bool) -> StopReason {
        if response.status == "incomplete" {
            switch response.incompleteDetails?.reason {
                case "max_output_tokens": return .maxTokens
                case "content_filter": return .refusal
                case let other?: return .other(other)
                case nil: return .other("incomplete")
            }
        }
        if refused { return .refusal }
        return called ? .toolUse : .endTurn
    }

    /// The failure an `error` event or a `failed` response reports.
    static func failure(code: OpenAIWireChunk.Code?, message: String) -> ProviderFailure {
        let status = if case .number(let number)? = code { number } else { Int?.none }
        let named = if case .text(let text)? = code { text } else { String?.none }
        // A Responses error has a code and no type, and codes are worded as OpenAI's types are (`rate_limit_exceeded`).
        let kind = ProviderFailure.Kind(openAIType: named, status: status, code: named, message: message)
        return ProviderFailure(
            kind: kind, message: message,
            contextWindow: kind == .contextOverflow ? ProviderFailure.Kind.contextWindow(describedIn: message) : nil)
    }

    /// The reasoning item in the form it is sent back: its id, its summary and its sealed content.
    static func reasoningPayload(id: String, summaries: [String], sealed: String) -> String {
        var writer = JSONStreamWriter()
        writer.object { item in
            item.field("type", "reasoning")
            item.field("id", id)
            item.key("summary")
            item.array { list in
                for text in summaries {
                    list.object { part in
                        part.field("type", "summary_text")
                        part.field("text", text)
                    }
                }
            }
            item.field("encrypted_content", sealed)
        }
        return String(decoding: writer.finish(), as: UTF8.self)
    }
}
