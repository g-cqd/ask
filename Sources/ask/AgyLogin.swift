internal import AskAI
internal import Foundation

/// `ask login agy`: the Antigravity sign-in, for the user's own Google account (ADR-0073).
///
/// The application's client secret is found in the installed `agy` and confirmed with Google before any URL is shown, so nobody
/// is asked to sign in only to be refused afterwards. The secret is never printed.
func agyLogin(file: CredentialFile) async {
    let transport = URLSessionTransport()
    do {
        let secret = try await installedClientSecret(transport: transport)
        let pending = AgyPendingSignIn.begin()
        print(
            "Open this URL and sign in with the Google account to use:\n\n  \(pending.url)\n\nThen paste the code it shows:"
        )
        guard let pasted = readLine(strippingNewline: true) else { fail("ask: no code entered.", code: 66) }
        let credentials = try await AgyAuthClient(transport: transport)
            .complete(pending, pasted: pasted, secret: secret, now: Date().timeIntervalSince1970)
        try file.saveAgy(credentials)
        // @dl:accept -- the closing lines of two sign-in commands read alike; the credential type and its store differ
        print("Signed in\(credentials.accountEmail.map { " as \($0)" } ?? ""). Credentials: \(file.url.path)")
    } catch {
        fail("ask: sign-in failed: \(error)", code: 77)
    }
}

/// The verified secret of the `agy` this machine has.
func installedClientSecret(transport: URLSessionTransport) async throws -> String {
    let path = AgyBinary.locate(environment: LaunchEnvironment.values, home: NSHomeDirectory()) {
        candidate in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    guard let path else { throw AgySecretError.binaryNotFound }
    let candidates = try AgyClientSecret.candidates(inFileAt: URL(filePath: path))
    guard !candidates.isEmpty else { throw AgySecretError.noCandidates }
    guard let secret = try await AgyClientSecret.verified(candidates, transport: transport) else {
        throw AgySecretError.notVerified
    }
    return secret
}
