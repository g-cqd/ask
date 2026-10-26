internal import AskAI
internal import Foundation

/// The sign-ins that end in an account the provider keeps: Claude's, Codex's and Antigravity's.
extension AccountLogin {
    func claude(connection: ConnectionRecord?, file: CredentialFile, replace: Bool) async throws -> String {
        // @dl:accept -- Claude's and Antigravity's sign-ins are twins over different credentials and endpoints: show a link, ask for the pasted code, exchange it, store it
        let pending = PendingSignIn.begin()
        interaction.say("Open this URL and sign in:\n\n  \(pending.url)\n")
        guard let pasted = await interaction.ask("Then paste the code it shows (code#state):", secret: false) else {
            throw Failure.nothingEntered
        }
        let credentials = try await ClaudeAuthClient(transport: transport)
            .complete(pending, pasted: pasted, now: Date().timeIntervalSince1970)
        if let connection {
            try NamedConnections.registry(environment: environment)
                .saveClaude(credentials, for: connection, replaceAccount: replace)
        } else {
            try file.saveClaudeSubscription(credentials)
        }
        if let email = credentials.accountEmail {
            NamedConnections.reportSharedAccount(.claude(email), connection: connection)
        }
        return "Signed in to Claude\(credentials.accountEmail.map { " as \($0)" } ?? "")."
    }

    func codex(device: Bool, connection: ConnectionRecord?, file: CredentialFile, replace: Bool) async throws -> String
    {
        let credentials: CodexCredentials
        if device {
            credentials = try await SignInRunner(clock: ContinuousClock())
                .run(CodexDeviceSignIn(transport: transport), show: self.show)
        } else {
            credentials = try await CodexBrowserSignIn(transport: transport)
                .run(show: self.show, paste: { await interaction.ask("Paste the address here:", secret: false) })
        }
        if let connection {
            try NamedConnections.registry(environment: environment)
                .saveCodex(credentials, for: connection, replaceAccount: replace)
        } else {
            try file.saveCodex(credentials)
        }
        NamedConnections.reportSharedAccount(.codex(credentials.accountID), connection: connection)
        return "Signed in to Codex."
    }

    /// The Antigravity sign-in, for the user's own Google account (ADR-0073). The application's client secret is found in the installed
    /// `agy` and confirmed with Google before any URL is shown, so nobody signs in only to be refused afterwards. It is never printed.
    func agy(file: CredentialFile) async throws -> String {
        let secret = try await installedClientSecret(transport: transport)
        let pending = AgyPendingSignIn.begin()
        interaction.say("Open this URL and sign in with the Google account to use:\n\n  \(pending.url)\n")
        guard let pasted = await interaction.ask("Then paste the code it shows:", secret: false) else {
            throw Failure.nothingEntered
        }
        let credentials = try await AgyAuthClient(transport: transport)
            .complete(pending, pasted: pasted, secret: secret, now: Date().timeIntervalSince1970)
        try file.saveAgy(credentials)
        return "Signed in to Antigravity\(credentials.accountEmail.map { " as \($0)" } ?? "")."
    }
}
