/// The user's answer to an approval question (roadmap 0019).
public enum ApprovalChoice: Sendable, Equatable {
    /// Allow this call only.
    case once
    /// Allow this call, and later ones it covers, until ask exits.
    case session
    /// Refuse it.
    case deny
}
