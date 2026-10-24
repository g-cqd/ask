internal import AemiJSON

extension AgyRequestEncoder {
    /// One part of a turn.
    enum Part {
        case text(String)
        case call(id: String, name: String, args: JSONObject, signature: String?)
        case result(id: String, name: String, content: String, isError: Bool)
    }

    /// One turn of the conversation on the wire.
    struct Content {
        var role: String
        var parts: [Part]

        /// The turns of `request` that have anything to say, in order.
        static func all(in request: ModelRequest) -> [Content] {
            var names: [String: String] = [:]
            for message in request.messages where message.role == .assistant {
                for case .toolCall(let id, let name, _) in message.blocks { names[id] = name }
            }
            let signs = AgyThoughtSignature.requiresSignature(model: request.model)
            let scheme = AgyThoughtSignature.scheme(model: request.model)
            return request.messages.compactMap { message in
                let parts =
                    message.role == .user
                    ? userParts(message.blocks, names: names)
                    : assistantParts(message.blocks, signs: signs, scheme: scheme)
                return parts.isEmpty ? nil : Content(role: message.role == .user ? "user" : "model", parts: parts)
            }
        }

        /// Results first, then text, because a result must answer the calls that came just before it.
        private static func userParts(_ blocks: [RequestBlock], names: [String: String]) -> [Part] {
            var results: [Part] = []
            var text: [Part] = []
            for block in blocks {
                switch block {
                    case .toolResult(let id, let content, let isError):
                        results.append(
                            .result(id: id, name: names[id] ?? "unknown_tool", content: content, isError: isError))
                    case .text(let value) where !value.isEmpty: text.append(.text(value))
                    default: break
                }
            }
            return results + text
        }

        /// Text and calls in the order the model wrote them. A signature this model issued rides on the call it preceded; a Gemini 3
        /// turn's first call with none gets the sentinel; reasoning of any other kind is not sent.
        private static func assistantParts(_ blocks: [RequestBlock], signs: Bool, scheme: String) -> [Part] {
            var parts: [Part] = []
            var pending: String?
            var firstCallSeen = false
            for block in blocks {
                switch block {
                    case .text(let value):
                        pending = nil
                        if !value.isEmpty { parts.append(.text(value)) }
                    case .thinking(_, let signature):
                        if signs, let issued = ReasoningProvenance.payload(of: signature, scheme: scheme) {
                            pending = issued
                        }
                    case .toolCall(let id, let name, let input):
                        let signature = pending ?? (signs && !firstCallSeen ? AgyThoughtSignature.sentinel : nil)
                        parts.append(.call(id: id, name: name, args: input, signature: signature))
                        pending = nil
                        firstCallSeen = true
                    case .redactedThinking, .toolResult: break
                }
            }
            return parts
        }

        func write(into writer: inout JSONStreamWriter) {
            writer.object { writer in
                writer.field("role", role)
                writer.key("parts")
                writer.array { writer in for part in parts { part.write(into: &writer) } }
            }
        }
    }
}

extension AgyRequestEncoder.Part {
    fileprivate func write(into writer: inout JSONStreamWriter) {
        writer.object { writer in
            switch self {
                case .text(let value): writer.field("text", value)
                case .call(let id, let name, let args, let signature):
                    Self.writeInvocation("functionCall", id: id, name: name, payload: "args", into: &writer) {
                        $0.raw(args.bytes)
                    }
                    if let signature { writer.field("thoughtSignature", signature) }
                case .result(let id, let name, let content, let isError):
                    Self.writeInvocation("functionResponse", id: id, name: name, payload: "response", into: &writer) {
                        $0.object { $0.field(isError ? "error" : "output", content) }
                    }
            }
        }
    }

    /// A call or a result: an object under `key` that names its call by id and name, then carries its payload.
    private static func writeInvocation(
        _ key: String, id: String, name: String, payload: String, into writer: inout JSONStreamWriter,
        _ body: (inout JSONStreamWriter) -> Void
    ) {
        writer.key(key)
        writer.object { writer in
            writer.field("id", id)
            writer.field("name", name)
            writer.key(payload)
            body(&writer)
        }
    }
}
