internal import Darwin

/// Words for a refusal the person reads: `/resume` showed `io(AskAgentCore.SessionFileError.Operation.open, errno: 2)` for a path that
/// does not exist (roadmap 0131).
extension SessionFileError: CustomStringConvertible {
    public var description: String {
        switch self {
            case .alreadyExists: "the file already exists"
            case .inUse: "this session is open in another ask"
            case .io(let operation, let errno): "could not \(operation) the file: \(String(cString: strerror(errno)))"
            // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are its own
            case .log(let failure): "the session file is not readable: \(failure)"
            case .tree(let failure): "the change is not valid: \(failure)"
            case .locked: "this session is encrypted; unlock it with your password or recovery code"
            case .otherKey: "this session was encrypted with another key than the one in use"
            case .unreadableHeader: "the session file's header is damaged"
        }
    }
}
