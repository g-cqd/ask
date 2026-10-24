internal import AskAI
internal import Foundation

/// Signs in to Codex, by browser (the default) or by a code typed at a link, and stores the credentials.
func codexLogin(device: Bool, file: CredentialFile, connection: ConnectionRecord? = nil, replaceAccount: Bool = false)
    async
{
    let transport = URLSessionTransport()
    do {
        let credentials: CodexCredentials
        if device {
            credentials = try await SignInRunner(clock: ContinuousClock())
                .run(
                    CodexDeviceSignIn(transport: transport), show: show)
        } else {
            credentials = try await CodexBrowserSignIn(transport: transport)
                .run(
                    show: show,
                    paste: {
                        say("Paste the address here:")
                        return await Task.detached { readLine(strippingNewline: true) }.value
                    })
        }
        if let connection {
            try NamedConnections.registry().saveCodex(credentials, for: connection, replaceAccount: replaceAccount)
        } else {
            try file.saveCodex(credentials)
        }
        print("Signed in to Codex. Credentials: \(file.url.path)")
        NamedConnections.reportSharedAccount(.codex(credentials.accountID), connection: connection)
    } catch {
        fail("ask: sign-in failed: \(error)", code: 77)
    }
}
