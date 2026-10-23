internal import AemiJSON

extension ResponsesRequestEncoder {
    /// The index of the last message that is a prompt: a user message with text. Reasoning is sent back only for what follows
    /// it, the tool loop in progress. Replaying older reasoning costs input tokens on every request and was not shown to help
    /// (ADR-0062).
    static func promptIndex(_ messages: [ModelMessage]) -> Int {
        messages.lastIndex { message in
            message.role == .user && message.blocks.contains { if case .text = $0 { true } else { false } }
        } ?? -1
    }

    /// The reasoning item stored in `signature`, when it is this protocol's, is JSON, and has the shape the server issued:
    /// a reasoning object with sealed content. A session file can be edited, so nothing else is ever spliced into a request.
    static func replayable(_ signature: String) -> String? {
        guard let payload = ReasoningProvenance.payload(of: signature, scheme: ResponsesStreamDecoder.scheme),
            let parsed = try? AemiJSON.parse(payload),
            parsed.root["type"].string == "reasoning", parsed.root["encrypted_content"].string?.isEmpty == false
        else { return nil }
        return payload
    }

    /// Whether `request` would carry reasoning under a dialect that replays it.
    static func carriesReplayableReasoning(_ request: ModelRequest) -> Bool {
        let start = promptIndex(request.messages) + 1
        return request.messages.dropFirst(start)
            .contains { message in
                message.role == .assistant
                    && message.blocks.contains { block in
                        if case .thinking(_, let signature) = block { replayable(signature) != nil } else { false }
                    }
            }
    }
}
