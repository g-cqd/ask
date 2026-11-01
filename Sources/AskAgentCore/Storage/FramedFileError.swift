/// Why a framed file could not be read or appended to.
enum FramedFileError: Error, Equatable {
    /// The bytes are not a framed file: a session in plain JSONL, for one.
    case notFramed
    /// The file ends inside its header.
    case truncatedHeader
    /// The header's check does not match, or it names what this version does not know.
    case damagedHeader
    /// A version of the format this one does not read.
    case unsupportedVersion(UInt8)
    /// The file is encrypted and no key was given.
    case needsKey
    /// The file's data key was sealed under another user key.
    case otherKey
    /// The file did not end cleanly, so it is rewritten rather than appended to (as a session file is, ADR-0013).
    case notResumable
    /// Compression failed, which zlib reports only when it runs out of memory.
    case compression
    /// What a record said could not be used: the error its reader raised.
    case record(SessionLogError)
}
