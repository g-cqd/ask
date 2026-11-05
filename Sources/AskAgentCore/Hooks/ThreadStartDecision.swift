/// What a hook answers when a thread would start.
public enum ThreadStartDecision: Sendable, Equatable {
    /// Start it as the hooks before left it.
    case allow
    /// Refuse it; the person is told `reason`.
    case block(String)
    /// Start it on this task instead; the next hook sees it.
    case rewrite(String)
}
