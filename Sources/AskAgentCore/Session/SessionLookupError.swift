/// Why `--resume` found no single session.
public enum SessionLookupError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No session's name starts with this.
    case notFound(String)
    /// Several do; the candidates are newest first.
    case ambiguous(String, candidates: [String])

    public var description: String {
        switch self {
            case .notFound(let query): "no session here is named \(query); `ask sessions` lists them"
            case .ambiguous(let query, let candidates):
                "\(query) names \(candidates.count) sessions: " + candidates.joined(separator: ", ")
        }
    }
}
