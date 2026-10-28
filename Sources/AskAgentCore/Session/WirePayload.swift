internal import AskAI
internal import Foundation

/// The persisted form of ``SessionPayload``: a `kind` and that kind's fields, mapped explicitly so the
/// session format is ask's own, not a provider type's derived encoding.
struct WirePayload: Codable {
    let value: SessionPayload

    private enum CodingKeys: String, CodingKey {
        case kind, text, summary, firstKept, blocks, id, model, stopReason, usage, callID, content, isError,
            destination, images
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
                let store = decoder.userInfo[SessionImageStore.userInfoKey] as? SessionImageStore
                var images: [ImagePart] = []
                var lost = 0
                for wire in try container.decodeIfPresent([WireImage].self, forKey: .images) ?? [] {
                    if let part = try wire.part(from: store) { images.append(part) } else { lost += 1 }
                }
                value = .toolResult(
                    callID: try container.decode(String.self, forKey: .callID),
                    content: try container.decode(String.self, forKey: .content) + Self.lostNote(lost),
                    isError: try container.decode(Bool.self, forKey: .isError), images: images)
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
            case .toolResult(let callID, let content, let isError, let images):
                try container.encode(Kind.toolResult, forKey: .kind)
                if !images.isEmpty {
                    let store = encoder.userInfo[SessionImageStore.userInfoKey] as? SessionImageStore
                    try container.encode(images.map { WireImage($0, in: store) }, forKey: .images)
                }
                try container.encode(callID, forKey: .callID)
                try container.encode(content, forKey: .content)
                try container.encode(isError, forKey: .isError)
        }
    }

    /// What the model is told of pictures a resumed session no longer has.
    private static func lostNote(_ count: Int) -> String {
        guard count > 0 else { return "" }
        let what = count == 1 ? "an image read here is" : "\(count) images read here are"
        return "\n[\(what) no longer available: the file in the session's images directory is missing or damaged]"
    }

    /// An image a tool returned: a reference to the file in the session's image store, or, when there is no store or it could not be
    /// written, the bytes inline as base64 (the form of older sessions, which stay readable).
    private struct WireImage: Codable {
        var mediaType: String
        var data: String?
        var sha256: String?

        struct Malformed: Error {}

        init(_ part: ImagePart, in store: SessionImageStore?) {
            mediaType = part.mediaType
            if let store, let name = try? store.put(part.data) {
                sha256 = name
            } else {
                data = Data(part.data).base64EncodedString()
            }
        }

        /// The image, or nil when it was kept in the store and the store no longer holds it intact.
        func part(from store: SessionImageStore?) throws -> ImagePart? {
            if let sha256 {
                return store?.get(sha256).map { ImagePart(mediaType: mediaType, data: $0) }
            }
            guard let data, let bytes = Data(base64Encoded: data) else { throw Malformed() }
            return ImagePart(mediaType: mediaType, data: [UInt8](bytes))
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
