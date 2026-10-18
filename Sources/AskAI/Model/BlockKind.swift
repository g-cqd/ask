/// What kind of content a block holds.
public enum BlockKind: Sendable, Equatable {
    case text
    case thinking
    /// Reasoning the provider withheld, returned verbatim on the next request.
    case redactedThinking(data: String)
    case toolUse(id: String, name: String)
    /// A block type this decoder does not know.
    case unrecognized(type: String)
}
