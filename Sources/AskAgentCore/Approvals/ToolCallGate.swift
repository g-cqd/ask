/// What the registry consults before a call runs (roadmap 0134): the policy, and who answers when it says to ask. An interactive
/// session has one; `ask -p` has none, so its calls run as the sandbox allows, the command line being the consent.
public struct ToolCallGate: Sendable {
    public let policy: ApprovalPolicy
    /// Asks the person; true allows the call. A grant for the session is the answerer's to remember.
    public let ask: @Sendable (ToolCallApproval) async -> Bool

    public init(policy: ApprovalPolicy, ask: @escaping @Sendable (ToolCallApproval) async -> Bool) {
        self.policy = policy
        self.ask = ask
    }
}
