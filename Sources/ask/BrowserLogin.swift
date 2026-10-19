internal import AskAI
internal import Foundation

/// Signs in through a browser and stores the key it issues, for the providers whose sign-in ends in an API key.
func browserLogin<Flow: BrowserSignIn>(_ flow: Flow, keyName: String, file: CredentialFile) async {
    do {
        let key = try await SignInRunner(clock: ContinuousClock())
            .run(flow) { url in
                print(
                    "Open this URL and sign in:\n\n  \(url.absoluteString)\n\nWaiting for you to finish in the browser…"
                )
            }
        try file.saveKey(key, for: keyName)
        print("Signed in. Key stored in \(file.url.path)")
    } catch {
        fail("ask: sign-in failed: \(error)", code: 77)
    }
}
