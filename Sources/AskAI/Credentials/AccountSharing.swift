/// Which other sign-ins are the same account as one that was just made.
public struct AccountSharing: Sendable, Equatable {
    /// Other named connections signed in as that account, sorted.
    public var connections: [String]
    /// Whether the default sign-in is that account too.
    public var defaultSignIn: Bool

    /// A description of what is shared.
    public init(connections: [String], defaultSignIn: Bool) {
        self.connections = connections
        self.defaultSignIn = defaultSignIn
    }

    /// The holders in words, or nil when the account is held once.
    private var holders: String? {
        let all = (defaultSignIn ? ["the default sign-in"] : []) + connections.map { "connection '\($0)'" }
        guard let last = all.last else { return nil }
        return all.count == 1 ? last : all.dropLast().joined(separator: ", ") + " and " + last
    }

    /// A short phrase for a listing, or nil when the account is held once.
    public var summary: String? { holders.map { "same account as " + $0 } }

    /// What to tell the person after a sign-in, or nil when the account is held once.
    public var notice: String? {
        guard let holders else { return nil }
        return
            "This is the same account as \(holders): separate grants of one account share its usage limits, so it is not a second account."
    }
}
