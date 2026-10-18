/// An opaque identifier unique within a session archive, including all its branches.
public struct EntryID: Sendable, Hashable, CustomStringConvertible {
    private let rawValue: String

    /// Wraps a persisted identifier. Archive validation rejects empty and oversized identifiers.
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// The identifier's persisted spelling; no ordering between identifiers is implied.
    public var description: String { rawValue }
}
