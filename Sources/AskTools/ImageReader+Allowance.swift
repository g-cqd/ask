internal import AskAI

extension ImageReader {
    /// What the model's provider accepts of one image, on top of ask's own bounds (2000 px, 4.5 MiB as base64).
    ///
    /// Taken from the provider's catalogue (Copilot reports a byte limit and media types per model). A byte limit is read as the
    /// image's own bytes, which is the stricter reading when the provider means base64 text only if it says so; nil means the
    /// provider said nothing, and ask's bounds alone apply.
    struct Allowance: Sendable, Equatable {
        var maximumBytes: Int?
        var mediaTypes: [String]

        init(_ limits: ImageLimits? = nil) {
            maximumBytes = limits?.maximumBytes
            mediaTypes = limits?.mediaTypes ?? []
        }

        /// Whether an image of `count` bytes is within both ask's bound and the provider's.
        func admits(count: Int) -> Bool {
            ImageReader.encodedSize(count) < ImageReader.maximumEncodedBytes
                && (maximumBytes.map { count <= $0 } ?? true)
        }

        /// Whether the provider takes `mediaType`; any when it listed none.
        func admits(type mediaType: String) -> Bool { mediaTypes.isEmpty || mediaTypes.contains(mediaType) }
    }
}
