/// How a check command ended, for ``CheckHook``.
public enum CheckOutcome: Sendable, Equatable {
    /// It exited 0.
    case passed
    /// It failed; what it printed.
    case failed(String)
    /// It did not finish: it timed out, was stopped, or could not start.
    case unfinished
}
