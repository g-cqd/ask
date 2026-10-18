/// Content retained in a session, independent of a provider's wire format.
public enum SessionPayload: Sendable, Equatable {
    /// A user turn.
    case user(String)
    /// An assistant turn.
    case assistant(String)
    /// A summary followed in context by messages from an ancestor boundary onward.
    case compaction(summary: String, firstKept: EntryID)
}
