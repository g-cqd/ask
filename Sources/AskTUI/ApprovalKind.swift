/// What sort of question an approval is (roadmap 0116), which decides its answers and the one checked to begin with.
public enum ApprovalKind: Sendable, Equatable {
    /// A request a grant can remember: allow this time, allow for the session, deny; "allow this time" checked.
    case grant
    /// The same answers for something that may destroy or overwrite: "deny" checked, so a stray Enter never allows it.
    case destructive
    /// Nothing to remember: yes or no, "no" checked.
    case confirm
}
