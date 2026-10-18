/// A conversation as a tree: entries are never removed, and the leaf selects the active branch.
///
/// Mirrors pi's session model. Branching, checkout and compaction change which entries a model sees,
/// never which entries exist. Every mutation validates before changing state, so a thrown error leaves
/// the tree exactly as it was.
///
/// Invariant: every parent precedes its children in ``entries``. That makes cycles unrepresentable, so
/// walking parents always terminates.
public struct SessionTree: Sendable, Equatable {
    /// Every entry, in archive order, across all branches.
    public private(set) var entries: [SessionEntry] = []
    /// The selected entry, or nil when the next append starts a new root.
    public private(set) var leaf: EntryID?
    private var positions: [EntryID: Int] = [:]
    private var nextOrdinal = 0

    /// The longest identifier a restored archive may contain, in UTF-8 bytes.
    public static let maximumIdentifierBytes = 128

    /// An empty session.
    public init() {}

    /// Restores an archive, validating identifiers, parent order and compaction boundaries.
    /// - Parameters:
    ///   - entries: archive entries, each parent before its children.
    ///   - leaf: the selected entry, or nil.
    /// - Throws: `SessionTreeError` for any malformed archive; nothing partial is returned.
    /// - Complexity: O(n × depth) for compaction checks, O(n) otherwise.
    public init(entries: [SessionEntry], leaf: EntryID?) throws(SessionTreeError) {
        for entry in entries {
            let size = entry.id.description.utf8.count
            guard size > 0, size <= Self.maximumIdentifierBytes else {
                throw .invalidIdentifier(entry.id)
            }
            guard positions[entry.id] == nil else { throw .duplicateEntry(entry.id) }
            if let parent = entry.parentID, positions[parent] == nil { throw .unknownEntry(parent) }
            try validate(entry.payload, under: entry.parentID)
            positions[entry.id] = self.entries.count
            self.entries.append(entry)
        }
        if let leaf, positions[leaf] == nil { throw .unknownEntry(leaf) }
        self.leaf = leaf
        nextOrdinal = entries.count
    }

    /// How many entries exist across all branches.
    public var count: Int { entries.count }

    /// The entry with this identifier, or nil.
    public func entry(_ id: EntryID) -> SessionEntry? {
        positions[id].map { entries[$0] }
    }

    /// Appends under the leaf and selects the new entry.
    /// - Returns: the new entry's identifier.
    /// - Throws: `invalidCompactionBoundary` when a compaction keeps an entry off its ancestry.
    @discardableResult
    public mutating func append(_ payload: SessionPayload) throws(SessionTreeError) -> EntryID {
        try validate(payload, under: leaf)
        let id = try freshIdentifier()
        positions[id] = entries.count
        entries.append(SessionEntry(id: id, parentID: leaf, payload: payload))
        leaf = id
        return id
    }

    /// Appends under an earlier entry and selects the new branch. Existing children stay intact.
    /// - Throws: `unknownEntry` for a missing parent, or a compaction-boundary error. The leaf is
    ///   unchanged on failure.
    @discardableResult
    public mutating func continuing(
        from parent: EntryID, with payload: SessionPayload
    ) throws(SessionTreeError) -> EntryID {
        guard positions[parent] != nil else { throw .unknownEntry(parent) }
        // One restore path for every failure `append` can raise, rather than validating twice.
        let previous = leaf
        leaf = parent
        do {
            return try append(payload)
        } catch {
            leaf = previous
            throw error
        }
    }

    /// Selects an existing entry, or nil to start a new root. Nothing is removed.
    /// - Throws: `unknownEntry` when the identifier is absent.
    public mutating func moveLeaf(to id: EntryID?) throws(SessionTreeError) {
        if let id, positions[id] == nil { throw .unknownEntry(id) }
        leaf = id
    }

    /// The active branch, root first.
    /// - Complexity: O(depth).
    public func activeBranch() -> [SessionEntry] { ancestry(of: leaf) }

    /// What a model sees: the latest compaction on the active branch, then the messages it kept, then
    /// everything after it. Older compactions in the kept range are omitted. Without a compaction, the
    /// whole branch.
    /// - Complexity: O(depth).
    public func context() -> [SessionEntry] {
        let branch = activeBranch()
        guard
            let compactionIndex = branch.lastIndex(where: { $0.payload.isCompaction }),
            case .compaction(_, let firstKept) = branch[compactionIndex].payload,
            let keptIndex = branch[..<compactionIndex].firstIndex(where: { $0.id == firstKept })
        else { return branch }
        let retained = branch[keptIndex ..< compactionIndex].filter { !$0.payload.isCompaction }
        return [branch[compactionIndex]] + retained + branch[(compactionIndex + 1)...]
    }

    /// A new session holding only the active branch, with identifiers preserved.
    /// - Throws: `SessionTreeError` if the branch fails archive validation.
    public func fork() throws(SessionTreeError) -> SessionTree {
        try SessionTree(entries: activeBranch(), leaf: leaf)
    }

    // MARK: - Private

    private func ancestry(of id: EntryID?) -> [SessionEntry] {
        var walked: [SessionEntry] = []
        var cursor = id
        while let current = cursor, let position = positions[current] {
            walked.append(entries[position])
            cursor = entries[position].parentID
        }
        return walked.reversed()
    }

    /// A compaction must keep a message on its own ancestry: the parent and everything above it.
    private func validate(_ payload: SessionPayload, under parent: EntryID?) throws(SessionTreeError) {
        guard case .compaction(_, let firstKept) = payload else { return }
        let lineage = ancestry(of: parent)
        guard let kept = lineage.first(where: { $0.id == firstKept }), !kept.payload.isCompaction else {
            throw .invalidCompactionBoundary(firstKept)
        }
    }

    /// The next unused local identifier. Skips identifiers a restored archive already holds.
    /// - Complexity: O(1) amortized; at most `count` skips in total.
    private mutating func freshIdentifier() throws(SessionTreeError) -> EntryID {
        while true {
            guard nextOrdinal < Int.max else { throw .identifierExhausted }
            let candidate = EntryID(String(nextOrdinal))
            nextOrdinal += 1
            if positions[candidate] == nil { return candidate }
        }
    }
}

extension SessionPayload {
    fileprivate var isCompaction: Bool {
        if case .compaction = self { return true }
        return false
    }
}
