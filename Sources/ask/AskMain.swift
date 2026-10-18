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
            try await printReply(to: prompt, model: model)
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

/// Streams one reply to standard output.
private func printReply(to prompt: String, model: String) async throws {
    let transport = URLSessionTransport()
    let auth: AnthropicClient.Auth
    if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
        auth = .apiKey(key)
    } else {
        do {
            auth = try await ClaudeAccess(file: .standard(), client: ClaudeAuthClient(transport: transport))
                .auth(now: Date().timeIntervalSince1970)
        } catch .signedOut {
            fail("ask: not signed in. Run `ask login`, or set ANTHROPIC_API_KEY.", code: 77)
        } catch {
            fail("ask: \(error)", code: 77)
        }
    }
    let request = ModelRequest(
        model: model, maxTokens: 16_384, systemPrompt: [],
        messages: [ModelMessage(role: .user, blocks: [.text(prompt)])],
        tools: [])
    do {
        for try await event in AnthropicClient(transport: transport).stream(request, auth: auth) {
            if case .textDelta(_, let text) = event { FileHandle.standardOutput.write(Data(text.utf8)) }
        }
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        fail("\nask: \(error)", code: 69)
    }
}

private func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
