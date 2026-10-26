internal import Foundation

/// What is signed in, and how to sign it in with a key or out again: the file's records as accounts.
extension CredentialFile {
    /// The key name Claude's API key is stored under, apart from the subscription's own record.
    public static let claudeKeyName = ProviderSettings.anthropic

    /// Every account the standard file and the environment give, in the order ask prefers them: Claude, Codex, Antigravity, then keys.
    /// - Throws: a ``CredentialFileError`` when the file cannot be read, never mistaken for being signed out.
    public func signedInAccounts(environment: [String: String]) throws(CredentialFileError) -> [SignedInAccount] {
        let stored = try read()
        var accounts: [SignedInAccount] = []
        if stored?.claude != nil {
            accounts.append(
                SignedInAccount(target: "claude", provider: ProviderSettings.anthropic, method: "subscription"))
        }
        if stored?.keys?[Self.claudeKeyName] != nil {
            accounts.append(SignedInAccount(target: "claude", provider: ProviderSettings.anthropic, method: "API key"))
        }
        if let variable = AnthropicEnvironmentAuth.variables.first(where: { !(environment[$0] ?? "").isEmpty }) {
            accounts.append(
                SignedInAccount(
                    target: "claude", provider: ProviderSettings.anthropic, method: "environment (\(variable))",
                    removable: false))
        }
        if stored?.codex != nil {
            accounts.append(SignedInAccount(target: "codex", provider: ProviderSettings.codex, method: "subscription"))
        }
        if stored?.agy != nil {
            accounts.append(SignedInAccount(target: "agy", provider: ProviderSettings.agy, method: "Google account"))
        }
        for name in (stored?.keys ?? [:]).keys.sorted() where name != Self.claudeKeyName {
            accounts.append(SignedInAccount(target: name, provider: name, method: "API key"))
        }
        for preset in ProviderPreset.all {
            guard let variable = preset.keyVariable, !(environment[variable] ?? "").isEmpty,
                stored?.keys?[preset.name] == nil
            else { continue }
            accounts.append(
                SignedInAccount(
                    target: preset.name, provider: preset.name, method: "environment (\(variable))", removable: false))
        }
        return accounts
    }

    /// Stores an API key for `provider`, replacing any. A Claude key replaces the Claude subscription in the same write, so one
    /// account has one way of signing in and nothing has to decide between two.
    /// - Throws: ``CredentialFileError``, and nothing is written when it does.
    public func saveAPIKey(_ key: String, for provider: String, now: Double) throws(CredentialFileError) {
        try transact(creating: true) {
            $0.keys = ($0.keys ?? [:]).merging([provider: StoredKey(key: key, obtainedAt: now)]) { _, new in new }
            if provider == Self.claudeKeyName { $0.claude = nil }
            return ((), true)
        }
    }

    /// Stores Claude's subscription, replacing any, and forgets the Claude API key in the same write: one account, one way in.
    /// - Throws: ``CredentialFileError``.
    public func saveClaudeSubscription(_ credentials: ClaudeCredentials) throws(CredentialFileError) {
        try transact(creating: true) {
            $0.claude = credentials
            $0.keys?[Self.claudeKeyName] = nil
            return ((), true)
        }
    }

    /// Forgets what `target` names: Claude's subscription and key, Codex's, Antigravity's, or the key stored under that name.
    /// - Returns: whether anything was stored under it.
    /// - Throws: ``CredentialFileError``.
    @discardableResult
    public func signOut(target: String) throws(CredentialFileError) -> Bool {
        try transact(creating: false) { stored in
            let before = stored
            switch target {
                case "claude", ProviderSettings.anthropic:
                    stored.claude = nil
                    stored.keys?[Self.claudeKeyName] = nil
                case "codex": stored.codex = nil
                case "agy": stored.agy = nil
                case "mistral-vibe": stored.keys?["mistral"] = nil
                default: stored.keys?[target] = nil
            }
            let changed =
                stored.claude != before.claude || stored.codex != before.codex || stored.agy != before.agy
                || stored.keys != before.keys
            return (changed, changed)
        }
    }
}
