/// Why a session file operation failed. A failed change leaves the in-memory session unchanged.
public enum SessionFileError: Error, Sendable, Equatable {
    /// The system call that failed.
    public enum Operation: Sendable, Equatable {
        case open, read, write, flush, link, rename, lock
    }

    /// The destination already exists. Creating and forking never overwrite.
    case alreadyExists
    /// Another `ask` has this session open: a session has one writer at a time (ADR-0024).
    case inUse
    /// A system call failed with this errno.
    case io(Operation, errno: Int32)
    /// The file could not be parsed or encoded.
    case log(SessionLogError)
    /// The change itself was invalid; nothing was written.
    case tree(SessionTreeError)
}
