/// How one task names another (ADR-0140).
public enum TaskLink: String, Codable, Sendable {
    /// It waits on the other; blocked while the other is not done.
    case blockedBy
    /// A loose link, with no effect on either's state.
    case related
}
