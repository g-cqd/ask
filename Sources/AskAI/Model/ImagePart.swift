internal import Foundation

/// An image a tool returned, ready to send: the bytes of a PNG, JPEG, GIF or WebP file already bounded in size.
///
/// Provider-neutral. Each request encoder shapes it for its wire (roadmap 0084).
public struct ImagePart: Sendable, Equatable {
    /// `image/png`, `image/jpeg`, `image/gif` or `image/webp`.
    public var mediaType: String
    public var data: [UInt8]

    public init(mediaType: String, data: [UInt8]) {
        self.mediaType = mediaType
        self.data = data
    }
}

extension ImagePart {
    /// The image as a `data:` URL, which is how OpenAI's chat and Responses wires carry one inline.
    public var dataURL: String { "data:\(mediaType);base64,\(Data(data).base64EncodedString())" }

    /// The most images a request holds when the provider does not say. A guess, kept well under what providers that do say allow.
    public static let defaultMaximumImages = 20

    /// The messages as they may be sent to a model (roadmap 0084), decided once for every wire.
    ///
    /// - When the model is not known to accept images (`accepts` is not true), every image becomes a line in its result saying why;
    ///   unknown and refused are told apart.
    /// - An image of a media type the provider does not list is replaced by a line saying so.
    /// - When the request holds more images than the provider allows, the oldest are replaced by a line, down to half the allowance
    ///   (at least one), so the start of the conversation stays the same for the next few images and a cached prefix survives.
    /// - Parameters:
    ///   - messages: the conversation.
    ///   - accepts: whether the model takes images: true only when the catalogue, the user's settings or ask's knowledge of the
    ///     provider says so.
    ///   - limits: what the provider says it accepts, or nil.
    /// - Returns: the messages to encode.
    public static func filtering(_ messages: [ModelMessage], accepts: Bool?, limits: ImageLimits? = nil)
        -> [ModelMessage]
    {
        var allowed = messages
        if accepts != true {
            let reason =
                accepts == false
                ? "this model does not accept images"
                : "it is not known that this model accepts images; \"images\": true on the model in providers.json says so"
            return replacing(allowed) { _, _ in reason }
        }
        if let types = limits?.mediaTypes, !types.isEmpty {
            allowed = replacing(allowed) { _, image in
                types.contains(image.mediaType) ? nil : "this model's provider does not take \(image.mediaType)"
            }
        }
        let total = allowed.reduce(0) { $0 + imageCount(in: $1) }
        let cap = max(1, limits?.maximumImages ?? defaultMaximumImages)
        guard total > cap else { return allowed }
        var drop = total - max(1, cap / 2)
        return replacing(allowed) { _, _ in
            guard drop > 0 else { return nil }
            drop -= 1
            return "an older image, removed to stay within the \(cap) a request may hold"
        }
    }

    private static func imageCount(in message: ModelMessage) -> Int {
        message.blocks.reduce(0) { count, block in
            if case .toolResult(_, _, _, let images) = block { count + images.count } else { count }
        }
    }

    /// Replaces each image for which `reason` gives a reason by a line in its result, oldest first.
    private static func replacing(_ messages: [ModelMessage], _ reason: (Int, ImagePart) -> String?) -> [ModelMessage] {
        var index = 0
        return messages.map { message in
            var message = message
            message.blocks = message.blocks.map { block in
                guard case .toolResult(let id, let content, let isError, let images) = block, !images.isEmpty else {
                    return block
                }
                var kept: [ImagePart] = []
                var notes: [String] = []
                for image in images {
                    if let why = reason(index, image) {
                        notes.append("[an image read here not sent: \(why)]")
                    } else {
                        kept.append(image)
                    }
                    index += 1
                }
                return .toolResult(
                    id: id, content: ([content] + notes).joined(separator: "\n"), isError: isError, images: kept)
            }
            return message
        }
    }

    /// What a wire that cannot put an image in a tool result says in the result, and in the user message that carries the picture.
    public static let attachedNote = "\n[the image is attached in the next message]"
    public static let attachedLead = "Image associated with the above tool call:"

    /// `content` with a line saying the images were not sent, for a wire that has no image encoding yet (roadmap 0084
    /// slice 3), so the model is told rather than left to think there was nothing.
    public static func noting(_ images: [ImagePart], in content: String) -> String {
        guard !images.isEmpty else { return content }
        let count = images.count == 1 ? "an image" : "\(images.count) images"
        return content + "\n[\(count) read here could not be sent: this model's connection has no image support yet]"
    }
}
