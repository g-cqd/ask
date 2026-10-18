internal import AemiJSON

/// The UTF-8 bytes of one JSON object, validated once, so it can be spliced into every later request
/// without being parsed again.
public struct JSONObject: Sendable, Equatable {
    /// The bytes were not one JSON object.
    public struct Invalid: Error, Sendable, Equatable {}

    /// The object's bytes, exactly as given.
    public let bytes: [UInt8]

    /// `{}`.
    public static let empty = JSONObject(trusted: Array("{}".utf8))

    private init(trusted bytes: [UInt8]) { self.bytes = bytes }

    /// Validates `bytes` as one JSON object.
    /// - Throws: ``Invalid`` for anything else, including other JSON values.
    public init(validating bytes: [UInt8]) throws(Invalid) {
        guard (try? AemiJSON.parse(bytes))?.root.isObject == true else { throw Invalid() }
        self.bytes = bytes
    }
}
