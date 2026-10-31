/// A finished sign-in to an account a provider keeps, Claude's or Codex's: what is stored, and whose account it is.
public enum SubscriptionSignIn: Sendable {
    case claude(ClaudeCredentials)
    case codex(CodexCredentials)

    /// The account signed in to; nil when Claude did not say which.
    public var identity: AccountIdentity? {
        switch self {
            case .claude(let credentials): credentials.accountEmail.map { .claude($0) }
            case .codex(let credentials): .codex(credentials.accountID)
        }
    }

    /// The subscription it is.
    public var kind: ConnectionKind {
        switch self {
            case .claude: .anthropic
            case .codex: .codex
        }
    }
}
