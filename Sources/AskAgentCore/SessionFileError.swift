/// Why a session file operation failed. A failed change leaves the in-memory session unchanged.
public enum SessionFileError: Error, Sendable, Equatable {
    /// The system call that failed.
    public enum Operation: Sendable, Equatable {
        case open, read, write, flush, link, rename
    }

    /// The destination already exists. Creating and forking never overwrite.
    case alreadyExists
    /// A system call failed with this errno.
    case io(Operation, errno: Int32)
    /// The file could not be parsed or encoded.
    case log(SessionLogError)
    /// The change itself was invalid; nothing was written.
    case tree(SessionTreeError)
}
