/// What a hook answers when a call would ask the person (roadmap 0192, ADR-0143). It never widens the sandbox: the sandbox's own
/// questions are not approvals.
public enum ApprovalDecision: Sendable, Equatable {
    /// Run the call, as if the person allowed it.
    case approve
    /// Do not run it; the model is told `reason`.
    case refuse(String)
    /// Leave it to the next hook, and then to the person.
    case ask
}
