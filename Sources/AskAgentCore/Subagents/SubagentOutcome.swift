/// What became of a subagent the model asked for.
public enum SubagentOutcome: Sendable, Equatable {
    /// It ran and merged: `summary` is what it reports.
    case report(name: String, summary: String)
    /// It did not start, for this reason.
    case refused(String)
}
