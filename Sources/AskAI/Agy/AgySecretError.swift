/// Why the Antigravity client secret could not be found. No case carries a candidate.
public enum AgySecretError: Error, Equatable, CustomStringConvertible {
    case binaryNotFound
    case unreadable(path: String)
    case noCandidates
    case notVerified
    case inconclusive(status: Int)

    public var description: String {
        switch self {
            case .binaryNotFound:
                "the Antigravity CLI (agy) was not found; install it, or set AGY_BINARY to its path"
            // @dl:accept -- per-case sentences in a description switch; the only shared shape is the switch, not any logic
            case .unreadable(let path): "cannot read \(path)"
            case .noCandidates: "the installed agy holds no OAuth client secret ask recognises"
            case .notVerified: "none of the strings in the installed agy is accepted by Google as its client secret"
            case .inconclusive(let status):
                "Google's token endpoint answered HTTP \(status), which says nothing about the client secret; try again later"
        }
    }
}
