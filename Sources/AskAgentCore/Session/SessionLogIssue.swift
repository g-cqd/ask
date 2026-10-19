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

    /// What was repaired, in a clause: `line 12 was not a valid record and was skipped`.
    public var explanation: String {
        switch self {
            case .missingHeader: "the file had no header, so it was read as the current format"
            case .tornFinalLine(let line): "the last line (line \(line)) was cut off mid-write and was dropped"
            case .unterminatedFinalLine(let line): "the last line (line \(line)) had no newline and was kept"
            case .malformedLine(let line): "line \(line) was not a valid record and was skipped"
            case .lineTooLong(let line): "line \(line) was too long and was skipped"
            case .duplicateEntry(let id, let line): "line \(line) reused the entry id \(id); the first was kept"
            case .invalidIdentifier(_, let line): "line \(line) had an invalid entry id and was skipped"
            case .orphanedEntry(let id, _, let line):
                "line \(line) (entry \(id)) had no parent, so it became a new root"
            case .droppedCompaction(_, _, let line):
                "line \(line) was a compaction pointing off its own branch, and was removed"
            case .ignoredLeaf(_, let line): "line \(line) selected an entry that does not exist, and was ignored"
        }
    }

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
