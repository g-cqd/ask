/// Why a session log could not be written or read. Reading never returns a partial session.
public enum SessionLogError: Error, Sendable, Equatable {
    /// The archive exceeds ``SessionLog/Limits/maximumArchiveBytes``; it was not split or parsed.
    case archiveTooLarge(Int)
    /// The first record is not a session header, or the archive is empty.
    case missingHeader
    /// The header names a format version this build cannot read.
    case unsupportedVersion(Int)
    /// A line exceeds ``SessionLog/Limits/maximumLineBytes``; it was not parsed.
    case lineTooLong(line: Int)
    /// The final line has no terminating newline: an interrupted write. Reported, never dropped.
    case tornFinalLine(line: Int)
    /// A line is blank, not JSON, an unknown record type, or a header out of place.
    case malformedLine(line: Int)
    /// The records parse but describe an invalid tree.
    case invalidArchive(SessionTreeError)
    /// A record could not be encoded.
    case encodingFailed
}
