/// What a hook answers when a compaction starts (roadmap 0192, ADR-0143).
public enum CompactionBeforeDecision: Sendable, Equatable {
    /// Summarise as usual.
    case allow
    /// Additional instructions appended to the summarisation prompt.
    case instructions(String)
}
