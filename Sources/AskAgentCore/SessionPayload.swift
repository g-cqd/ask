public import AskAI

/// Content retained in a session, independent of a provider's wire format.
public enum SessionPayload: Sendable, Equatable {
    /// A user turn.
    case user(String)
    /// An assistant turn of plain text.
    case assistant(String)
    /// A complete assistant response, kept whole so a resumed session replays requests exactly: thinking
    /// signatures, tool calls and usage included.
    case response(AssembledResponse)
    /// The result of one tool call, recorded as soon as it is known.
    case toolResult(callID: String, content: String, isError: Bool)
    /// A summary followed in context by messages from an ancestor boundary onward.
    case compaction(summary: String, firstKept: EntryID)
}
