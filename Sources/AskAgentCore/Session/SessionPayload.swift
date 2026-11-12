public import AskAI

/// Content retained in a session, independent of a provider's wire format.
public enum SessionPayload: Sendable, Equatable {
    /// Routing metadata, never part of a model's input or replayed as a prompt.
    case destination(SessionDestination)
    /// A user turn.
    case user(String, images: [ImagePart] = [])
    /// An assistant turn of plain text.
    case assistant(String)
    /// A complete assistant response, kept whole so a resumed session replays requests exactly: thinking
    /// signatures, tool calls and usage included.
    case response(AssembledResponse, rewrite: RequestRewrite? = nil)
    /// The result of one tool call, recorded as soon as it is known, with what the tool did for the screen (``ToolFacts``).
    case toolResult(
        callID: String,
        content: String,
        isError: Bool,
        images: [ImagePart] = [],
        facts: ToolFacts = ToolFacts()
    )
    /// A summary followed in context by messages from an ancestor boundary onward.
    case compaction(summary: String, firstKept: EntryID)
    /// An entry of a kind this build does not know, from a newer ask (ADR-0144): kept, not read. It adds nothing to a request or the
    /// screen, its children still hang from it, and its record is written back as it was, `line` without the newline.
    case unrecognized(kind: String, line: [UInt8])
}
