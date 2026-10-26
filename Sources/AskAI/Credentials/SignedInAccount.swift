/// One way ask can reach a provider right now: a subscription, a key it stored, or a key the environment holds.
public struct SignedInAccount: Sendable, Equatable {
    /// What `ask logout` and `/logout` take to forget it.
    public let target: String
    /// The name `--provider` and `/model` use for the models it reaches.
    public let provider: String
    /// How it signs in, for a person: `subscription`, `API key`, `environment (VARIABLE)`.
    public let method: String
    /// Whether ask can forget it: a key in the environment is the shell's, not ask's.
    public let removable: Bool

    /// An account.
    public init(target: String, provider: String, method: String, removable: Bool = true) {
        self.target = target
        self.provider = provider
        self.method = method
        self.removable = removable
    }
}
