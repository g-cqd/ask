/// One repair ``SessionLog/recover(_:limits:)`` made while loading a damaged log. Lines are 1-based.
public enum SessionLogIssue: Sendable, Equatable {
    /// No header preceded the first record; the records were read as the current format.
    case missingHeader
    /// The final line was cut off mid-record by an interrupted write, and was dropped.
    case tornFinalLine(line: Int)
    /// The final record is complete but lacks its newline. It was kept.
    case unterminatedFinalLine(line: Int)
    /// A line was blank, not JSON, an unknown record type, or a misplaced header. It was skipped.
    case malformedLine(line: Int)
    /// A line exceeded the line limit and was skipped unparsed.
    case lineTooLong(line: Int)
    /// A second entry reused an identifier. The first was kept, since later children were written against it.
    case duplicateEntry(EntryID, line: Int)
    /// An entry had an empty or oversized identifier and was skipped.
    case invalidIdentifier(EntryID, line: Int)
    /// An entry's parent was missing, so it was kept as a new root and its subtree stays reachable.
    case orphanedEntry(EntryID, missingParent: EntryID, line: Int)
    /// A compaction kept an entry off its own branch. It was removed and its children re-parented to its
    /// parent, so the raw messages it would have summarised stay in context.
    case droppedCompaction(EntryID, boundary: EntryID, line: Int)
    /// A leaf record named an entry not yet written. It was ignored; the leaf stays where it was.
    case ignoredLeaf(EntryID, line: Int)

    /// The error strict decoding raises for this issue.
    var strictError: SessionLogError {
        switch self {
            case .missingHeader: .missingHeader
            case .tornFinalLine(let line), .unterminatedFinalLine(let line): .tornFinalLine(line: line)
            case .malformedLine(let line): .malformedLine(line: line)
            case .lineTooLong(let line): .lineTooLong(line: line)
            case .duplicateEntry(let id, _): .invalidArchive(.duplicateEntry(id))
            case .invalidIdentifier(let id, _): .invalidArchive(.invalidIdentifier(id))
            case .orphanedEntry(_, let missing, _): .invalidArchive(.unknownEntry(missing))
            case .droppedCompaction(_, let boundary, _): .invalidArchive(.invalidCompactionBoundary(boundary))
            case .ignoredLeaf(let id, _): .invalidArchive(.unknownEntry(id))
        }
    }
}

/// A session loaded from a possibly damaged log, with every repair that was needed.
public struct RecoveredSession: Sendable, Equatable {
    /// A valid tree: re-saving it produces a log that decodes strictly with no issues.
    public let tree: SessionTree
    /// The repairs, in line order. Empty for an undamaged log.
    public let issues: [SessionLogIssue]
}
