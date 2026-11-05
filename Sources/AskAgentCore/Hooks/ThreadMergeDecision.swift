/// What a hook answers before a thread's summary is written.
public enum ThreadMergeDecision: Sendable, Equatable {
    /// Summarise as usual.
    case allow
    /// Instructions added to the summary's.
    case instructions(String)
}
