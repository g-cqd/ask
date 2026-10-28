/// What a provider says it accepts of images in one request: how many, how large each, and of which media types.
///
/// Each part is nil, or empty, when the provider did not say; an unreported limit is unknown and not unlimited (roadmap 0084).
public struct ImageLimits: Codable, Sendable, Equatable {
    /// The most images one request may hold.
    public var maximumImages: Int?
    /// The most bytes one image may have, as the provider counts them.
    public var maximumBytes: Int?
    /// The media types accepted, such as `image/png`; empty when not reported.
    public var mediaTypes: [String]

    /// Limits with these parts.
    public init(maximumImages: Int? = nil, maximumBytes: Int? = nil, mediaTypes: [String] = []) {
        self.maximumImages = maximumImages
        self.maximumBytes = maximumBytes
        self.mediaTypes = mediaTypes
    }

    /// A short description for a table: `10 images, 10.0 MB, png pdf`, or `unknown`.
    public var summary: String {
        var parts: [String] = []
        if let maximumImages { parts.append("\(maximumImages) images") }
        if let maximumBytes { parts.append("\(maximumBytes / 1_000_000) MB") }
        if !mediaTypes.isEmpty {
            parts.append(mediaTypes.map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: " "))
        }
        return parts.isEmpty ? "unknown" : parts.joined(separator: ", ")
    }
}
