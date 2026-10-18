/// Invalid session operations or archive structure. Failures leave the tree unchanged.
public enum SessionTreeError: Error, Sendable, Equatable {
    /// A referenced entry does not exist, or its parent appears later in the archive.
    case unknownEntry(EntryID)
    /// More than one archived entry has this identifier.
    case duplicateEntry(EntryID)
    /// Identifiers must be nonempty and at most 128 UTF-8 bytes.
    case invalidIdentifier(EntryID)
    /// A compaction must retain a message on its own ancestry, not another branch or summary.
    case invalidCompactionBoundary(EntryID)
    /// The local identifier counter cannot advance without overflow.
    case identifierExhausted
}
