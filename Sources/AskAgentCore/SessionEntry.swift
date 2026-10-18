/// An immutable archive entry. Parents must precede children in archive order.
public struct SessionEntry: Sendable, Equatable {
    /// Stable archive identifier.
    public let id: EntryID
    /// An earlier archive entry, or nil for a root.
    public let parentID: EntryID?
    /// The content of this entry.
    public let payload: SessionPayload

    /// Builds an entry for archive restoration; the tree validates identifiers and ancestry.
    /// - Parameters:
    ///   - id: identifier unique in the archive.
    ///   - parentID: an earlier entry, or nil.
    ///   - payload: message or compaction content.
    public init(id: EntryID, parentID: EntryID?, payload: SessionPayload) {
        self.id = id
        self.parentID = parentID
        self.payload = payload
    }
}
