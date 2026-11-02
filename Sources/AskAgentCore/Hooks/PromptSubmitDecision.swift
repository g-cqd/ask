/// What a hook answers when a message from the person would enter the conversation (roadmap 0192, ADR-0143).
public enum PromptSubmitDecision: Sendable, Equatable {
    /// Let it in as the hooks before left it.
    case allow
    /// Keep it out; the person gets it back with `reason`.
    case block(String)
    /// Send this text instead; the next hook sees it.
    case rewrite(String)
    /// Add this text after the message, labelled with the hook's name.
    case context(String)
}
