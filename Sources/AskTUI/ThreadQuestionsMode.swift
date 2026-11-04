/// Where a thread's question appears while the person is elsewhere (`threads.questions`, roadmap 0195, note n19).
public enum ThreadQuestionsMode: Sendable, Equatable {
    /// At once, in whatever is shown, named for its thread.
    case focus
    /// The same, once it has waited this long.
    case after(Duration)
    /// Only in its lane; the sidebar's `?` and the counts say it waits.
    case lane
}
