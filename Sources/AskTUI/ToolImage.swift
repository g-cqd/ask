/// A picture a tool returned, as the screen shows it (roadmap 0208, STUB).
public struct ToolImage: Sendable, Equatable {
    public let mediaType: String
    public let data: [UInt8]

    public init(mediaType: String, data: [UInt8]) {
        self.mediaType = mediaType
        self.data = data
    }

    /// Its width and height in pixels, read from its header; nil when the header says neither.
    public var pixelSize: (width: Int, height: Int)? { ImagePixelSize.read(data) }
}
