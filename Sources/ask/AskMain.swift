/// The `ask` executable: argument parsing and the composition root, nothing else.
///
/// Everything with behaviour lives in library targets so it can be tested; this file only binds them.

internal import ArgumentParser
internal import AskAI
internal import AskCore
internal import AskTUI
internal import Foundation

@main
struct Ask: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "A terminal coding agent: reliable, fast, light.",
        subcommands: [Login.self, Logout.self])

    @Flag(help: "Print the four performance budgets as JSON and exit. Read by Scripts/measure-budgets.py.")
    var budgets = false

    @Option(
        name: [.short, .customLong("print")], help: "Send one prompt, stream the reply to standard output, and exit.")
    var prompt: String?

    @Option(help: "The model for --print.")
    var model = "claude-sonnet-5-5"

    func run() async throws {
        if budgets {
            FileHandle.standardOutput.write(Data(try Budget.reportJSON()))
            return
        }
        if let prompt {
            await runPrompt(prompt, model: model)
            return
        }
        do {
            try runAskTUI()
        } catch {
            // The loop has already restored the terminal by the time an error reaches here.
            fail("ask: \(error)", code: 70)
        }
    }
}

/// `ask login`: sign in with a Claude subscription.
struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Sign in with a Claude subscription.")

    func run() async throws {
        let pending = PendingSignIn.begin()
        print("Open this URL and sign in:\n\n  \(pending.url)\n\nThen paste the code it shows (code#state):")
        guard let pasted = readLine(strippingNewline: true) else { fail("ask: no code entered.", code: 66) }
        let file = CredentialFile.standard()
        do {
            let credentials = try await ClaudeAuthClient(transport: URLSessionTransport())
                .complete(pending, pasted: pasted, now: Date().timeIntervalSince1970)
            try file.saveClaude(credentials)
            print("Signed in\(credentials.accountEmail.map { " as \($0)" } ?? ""). Credentials: \(file.url.path)")
        } catch {
            fail("ask: sign-in failed: \(error)", code: 77)
        }
    }
}

/// `ask logout`: forget stored credentials.
struct Logout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget stored credentials.")

    func run() throws {
        try CredentialFile.standard().remove()
        print("Signed out.")
    }
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
