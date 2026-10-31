extension ConnectionRegistry {
    /// Where a sign-in without a name goes (roadmap 0092): the default when it is empty, holds the same account, or `replace` is set;
    /// else the connection already holding the account; else a new connection, so the default's account is kept.
    /// - Parameters:
    ///   - identity: the account just signed in to; nil when the provider did not say, which never replaces a signed-in default.
    ///   - kind: the provider, whose default sign-in is compared.
    ///   - defaultFile: the file holding the default sign-ins.
    ///   - replace: whether the person asked to replace the default's account.
    ///   - reserved: configured names a new connection must not take.
    /// - Returns: where to store the sign-in.
    /// - Throws: when the default file or a registration cannot be read.
    public func placement(
        of identity: AccountIdentity?, kind: ConnectionKind, defaultFile: CredentialFile, replace: Bool,
        reserved: [String] = []
    ) throws -> SignInPlacement {
        let current: (signedIn: Bool, identity: AccountIdentity?)
        switch kind {
            case .codex: current = try defaultFile.loadCodex().map { (true, .codex($0.accountID)) } ?? (false, nil)
            case .anthropic:
                current =
                    try defaultFile.loadClaude().map { (true, $0.accountEmail.map { .claude($0.lowercased()) }) } ?? (
                        false, nil
                    )
        }
        let normalized = identity.map(Self.normalized)
        if replace || !current.signedIn || (normalized != nil && normalized == current.identity) {
            return .defaultSignIn
        }
        if let identity, let holder = try connections(as: identity).first { return .connection(holder) }
        let taken = Set(try list().records.map(\.name) + reserved.map { $0.lowercased() })
        let stem = identity.flatMap(Self.stem) ?? ""
        let first = stem.isEmpty ? nil : "\(kind.signInName)-\(stem)"
        if let first, !taken.contains(first) { return .newConnection(first) }
        let base = first ?? kind.signInName
        let number = (2...).first { !taken.contains("\(base)-\($0)") } ?? 2
        return .newConnection("\(base)-\(number)")
    }

    private static func normalized(_ identity: AccountIdentity) -> AccountIdentity {
        if case .claude(let email) = identity { return .claude(email.lowercased()) }
        return identity
    }

    /// A name from the account's address: its local part, lowercased, other characters as `-`. A Codex account id says nothing to a
    /// person, so Codex connections are numbered.
    private static func stem(_ identity: AccountIdentity) -> String? {
        guard case .claude(let email) = identity, let local = email.lowercased().split(separator: "@").first else {
            return nil
        }
        let word = String(local.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "-" })
        let trimmed = word.drop { !($0.isLetter || $0.isNumber) }.prefix(48)
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}

extension ConnectionRegistry {
    /// Stores a sign-in made without a name where ``placement(of:kind:defaultFile:replace:reserved:)`` says.
    /// - Returns: where it went.
    /// - Throws: a file, lock or registration error; nothing is stored then.
    public func storeSignIn(
        _ signIn: SubscriptionSignIn, defaultFile: CredentialFile, replace: Bool, reserved: [String] = []
    ) throws -> SignInPlacement {
        let placement = try placement(
            of: signIn.identity, kind: signIn.kind, defaultFile: defaultFile, replace: replace, reserved: reserved)
        if let record = try record(for: placement, kind: signIn.kind, reserved: reserved) {
            try save(signIn, for: record)
        } else {
            switch signIn {
                case .claude(let credentials): try defaultFile.saveClaudeSubscription(credentials)
                case .codex(let credentials): try defaultFile.saveCodex(credentials)
            }
        }
        return placement
    }

    /// Stores `signIn` in the connection `record`, which must be of its kind; a changed account needs `replaceAccount`.
    /// - Throws: ``ConnectionError`` when the connection changed or holds another account, or a file or lock error.
    public func save(_ signIn: SubscriptionSignIn, for record: ConnectionRecord, replaceAccount: Bool = false) throws {
        switch signIn {
            case .claude(let credentials): try saveClaude(credentials, for: record, replaceAccount: replaceAccount)
            case .codex(let credentials): try saveCodex(credentials, for: record, replaceAccount: replaceAccount)
        }
    }

    /// The connection a placement names, registered when it is new; nil for the default sign-in.
    private func record(for placement: SignInPlacement, kind: ConnectionKind, reserved: [String]) throws
        -> ConnectionRecord?
    {
        switch placement {
            case .defaultSignIn: return nil
            case .connection(let name):
                guard let record = try list().records.first(where: { $0.name == name }) else {
                    throw ConnectionError.changed(name)
                }
                return record
            case .newConnection(let name): return try register(name: name, provider: kind, reserved: reserved)
        }
    }
}
