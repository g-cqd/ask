internal import AskAI
internal import Foundation

/// Says `text` to the user at once. `print` is buffered when stdout is a pipe or a file, so a prompt written with it
/// would not appear until the sign-in it asks for had ended.
func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

/// What a browser sign-in shows the user: the link, what to do there if it takes more than opening it, and that ask waits.
func show(_ prompt: SignInPrompt) {
    var text = "Open this URL and sign in:\n\n  \(prompt.url.absoluteString)\n"
    if let instructions = prompt.instructions { text += "\n\(instructions)\n" }
    say(text + "\nWaiting for you to finish in the browser…")
}

/// Signs in through a browser and stores the key it issues, for the providers whose sign-in ends in an API key.
func browserLogin<Flow: KeySignIn>(_ flow: Flow, keyName: String, file: CredentialFile) async {
    do {
        let key = try await SignInRunner(clock: ContinuousClock()).run(flow, show: show)
        try file.saveKey(key, for: keyName)
        print("Signed in. Key stored in \(file.url.path)")
    } catch {
        fail("ask: sign-in failed: \(error)", code: 77)
    }
}
