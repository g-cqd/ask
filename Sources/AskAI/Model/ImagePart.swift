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

    /// The messages as they may be sent to a model: when it is not known to accept images, every image is replaced by a line in
    /// its result saying so, once for all wires (roadmap 0084). `accepts` is true only when the model's catalogue, the user's
    /// settings or ask's own knowledge of the provider says so; false and unknown both withhold, and say which.
    public static func filtering(_ messages: [ModelMessage], accepts: Bool?) -> [ModelMessage] {
        guard accepts != true else { return messages }
        let reason =
            accepts == false
            ? "this model does not accept images"
            : "it is not known that this model accepts images; \"images\": true on the model in providers.json says so"
        return messages.map { message in
            var message = message
            message.blocks = message.blocks.map { block in
                guard case .toolResult(let id, let content, let isError, let images) = block, !images.isEmpty else {
                    return block
                }
                return .toolResult(
                    id: id, content: content + "\n[\(describe(images)) read here not sent: \(reason)]",
                    isError: isError,
                    images: [])
            }
            return message
        }
    }

    /// What a wire that cannot put an image in a tool result says in the result, and in the user message that carries the picture.
    public static let attachedNote = "\n[the image is attached in the next message]"
    public static let attachedLead = "The image(s) from the tool result above:"

    private static func describe(_ images: [ImagePart]) -> String {
        images.count == 1 ? "an image" : "\(images.count) images"
    }

    /// `content` with a line saying the images were not sent, for a wire that has no image encoding yet (roadmap 0084
    /// slice 3), so the model is told rather than left to think there was nothing.
    public static func noting(_ images: [ImagePart], in content: String) -> String {
        guard !images.isEmpty else { return content }
        let count = images.count == 1 ? "an image" : "\(images.count) images"
        return content + "\n[\(count) read here could not be sent: this model's connection has no image support yet]"
    }
}
