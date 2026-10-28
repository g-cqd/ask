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
    /// `content` with a line saying the images were not sent, for a wire that has no image encoding yet (roadmap 0084
    /// slice 3), so the model is told rather than left to think there was nothing.
    public static func noting(_ images: [ImagePart], in content: String) -> String {
        guard !images.isEmpty else { return content }
        let count = images.count == 1 ? "an image" : "\(images.count) images"
        return content + "\n[\(count) read here could not be sent: this model's connection has no image support yet]"
    }
}
