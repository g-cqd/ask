/// What sort of question an approval is (roadmap 0116), which decides its answers and the one checked to begin with.
public enum ApprovalKind: Sendable, Equatable {
    /// A request a grant can remember: allow this time, allow for the session, deny; "allow this time" checked.
    case grant
    /// The same answers for something that may destroy or overwrite: "deny" checked, so a stray Enter never allows it.
    case destructive
    /// Nothing to remember: yes or no, "no" checked.
    case confirm
    /// A command line (roadmap 0134): this time, its subcommands for the session, its programs for the session, or deny; "this time"
    /// checked. With no phrases (a line a grant cannot cover), only this time or deny.
    case command(phrases: [String], programs: [String])
}
