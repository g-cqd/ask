/// What a hook answers when a session opens, is resumed or is switched to (roadmap 0192, ADR-0143).
public enum SessionStartDecision: Sendable, Equatable {
    /// Observe only.
    case allow
    /// Add `text` to the conversation, labelled with the hook's name.
    case context(String)
}
