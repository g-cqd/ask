internal import AskAI

/// The persisted form of ``SessionPayload``: a `kind` and that kind's fields, mapped explicitly so the
/// session format is ask's own, not a provider type's derived encoding.
struct WirePayload: Codable {
    let value: SessionPayload

    private enum CodingKeys: String, CodingKey {
        case kind, text, summary, firstKept, blocks, id, model, stopReason, usage, callID, content, isError, destination
    }

    private enum Kind: String, Codable {
        case user, assistant, compaction, response, destination
        case toolResult = "tool_result"
    }

    init(value: SessionPayload) { self.value = value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
            case .destination: value = .destination(try container.decode(SessionDestination.self, forKey: .destination))
            case .user: value = .user(try container.decode(String.self, forKey: .text))
            case .assistant: value = .assistant(try container.decode(String.self, forKey: .text))
            case .compaction:
                value = .compaction(
                    summary: try container.decode(String.self, forKey: .summary),
                    firstKept: EntryID(try container.decode(String.self, forKey: .firstKept)))
            case .response:
                value = .response(
                    AssembledResponse(
                        id: try container.decode(String.self, forKey: .id),
                        model: try container.decode(String.self, forKey: .model),
                        blocks: try container.decode([WireBlock].self, forKey: .blocks).map { try $0.block() },
                        stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason)
                            .map(StopReason.init(wire:)),
                        usage: try container.decode(WireUsage.self, forKey: .usage).tokens, unrecognized: []))
            case .toolResult:
                value = .toolResult(
                    callID: try container.decode(String.self, forKey: .callID),
                    content: try container.decode(String.self, forKey: .content),
                    isError: try container.decode(Bool.self, forKey: .isError))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch value {
            // @dl:accept -- routing is explicitly encoded as session data, like the log envelope, not as Swift's synthesized enum format
            case .destination(let destination):
                try container.encode(Kind.destination, forKey: .kind)
                try container.encode(destination, forKey: .destination)
            case .user(let text):
                try container.encode(Kind.user, forKey: .kind)
                try container.encode(text, forKey: .text)
            case .assistant(let text):
                try container.encode(Kind.assistant, forKey: .kind)
                try container.encode(text, forKey: .text)
            case .compaction(let summary, let firstKept):
                try container.encode(Kind.compaction, forKey: .kind)
                try container.encode(summary, forKey: .summary)
                try container.encode(firstKept.description, forKey: .firstKept)
            case .response(let response):
                try container.encode(Kind.response, forKey: .kind)
                try container.encode(response.id, forKey: .id)
                try container.encode(response.model, forKey: .model)
                try container.encode(response.blocks.map(WireBlock.init), forKey: .blocks)
                try container.encodeIfPresent(response.stopReason?.wire, forKey: .stopReason)
                try container.encode(WireUsage(response.usage), forKey: .usage)
            case .toolResult(let callID, let content, let isError):
                try container.encode(Kind.toolResult, forKey: .kind)
                try container.encode(callID, forKey: .callID)
                try container.encode(content, forKey: .content)
                try container.encode(isError, forKey: .isError)
        }
    }

    /// One assistant block on the wire. Tool input is kept as its exact JSON text.
    private struct WireBlock: Codable {
        var type: String
        var text: String?
        var signature: String?
        var data: String?
        var id: String?
        var name: String?
        var input: String?

        struct Malformed: Error {}

        init(_ block: ContentBlock) {
            switch block {
                case .text(let text): self.init(type: "text", text: text)
                case .thinking(let text, let signature): self.init(type: "thinking", text: text, signature: signature)
                case .redactedThinking(let data): self.init(type: "redacted_thinking", data: data)
                case .toolCall(let id, let name, let input):
                    self.init(
                        type: "tool_call", id: id, name: name, input: String(decoding: input.bytes, as: UTF8.self))
                case .unrecognized(let type): self.init(type: "unrecognized", name: type)
            }
        }

        private init(
            type: String, text: String? = nil, signature: String? = nil, data: String? = nil, id: String? = nil,
            name: String? = nil, input: String? = nil
        ) {
            (self.type, self.text, self.signature, self.data) = (type, text, signature, data)
            (self.id, self.name, self.input) = (id, name, input)
        }

        func block() throws -> ContentBlock {
            switch (type, text, signature, data, id, name, input) {
                case ("text", let text?, _, _, _, _, _): return .text(text)
                case ("thinking", let text?, let signature?, _, _, _, _):
                    return .thinking(text: text, signature: signature)
                case ("redacted_thinking", _, _, let data?, _, _, _): return .redactedThinking(data: data)
                case ("tool_call", _, _, _, let id?, let name?, let input?):
                    return .toolCall(id: id, name: name, input: try JSONObject(validating: Array(input.utf8)))
                case ("unrecognized", _, _, _, _, let name?, _): return .unrecognized(type: name)
                default: throw Malformed()
            }
        }
    }

    /// Token usage on the wire. Counts the provider did not report are omitted, never written as zero.
    private struct WireUsage: Codable {
        var input: Int?
        var output: Int?
        var cacheRead: Int?
        var cacheCreation: Int?

        init(_ usage: TokenUsage) {
            (input, output, cacheRead, cacheCreation) = (
                usage.input, usage.output, usage.cacheRead, usage.cacheCreation
            )
        }

        var tokens: TokenUsage {
            TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
        }
    }
}
