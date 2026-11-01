/// `taskScope` (ADR-0140): whose task list a session uses.
public enum TaskScope: String, Sendable, CaseIterable {
    /// Its own, beside the session file, forked with it.
    case session
    /// One list for every session of the workspace.
    case workspace

    static let choices = #""session" or "workspace""#
}
