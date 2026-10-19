/// The `ask` executable: argument parsing and the composition root, nothing else.
///
/// Everything with behaviour lives in library targets so it can be tested; this file only binds them.

internal import ArgumentParser
internal import AskAI
internal import AskAgentCore
internal import AskCore
internal import AskTUI
internal import Foundation

@main
struct Ask: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "A terminal coding agent: reliable, fast, light.",
        subcommands: [Login.self, Logout.self, Sessions.self])

    @Flag(help: "Print the four performance budgets as JSON and exit. Read by Scripts/measure-budgets.py.")
    var budgets = false

    @Option(
        name: [.short, .customLong("print")],
        help: "Run one prompt with the tools, stream the answer to standard output, and exit.")
    var prompt: String?

    @Option(help: "The model to use. Default: the provider's default model.")
    var model: String?

    @Option(
        help: "The provider: \"anthropic\", or a name from ~/.config/ask/providers.json. Default: the file's default.")
    var provider: String?

    @Option(help: "The most model requests one prompt may make before ask stops it.")
    var maxTurns = 100

    @Option(
        help: ArgumentHelp(
            "Compact the conversation once its context reaches this many tokens; 0 only when the window is full.",
            valueName: "tokens"))
    var compactAt = AgentSettings.defaultCompactAtTokens

    @Flag(name: [.short, .customLong("continue")], help: "Continue the session written last in this project.")
    var continueLatest = false

    @Option(
        name: [.short, .customLong("resume")],
        help: "Resume a session by name, unique name prefix, or path. `ask sessions` lists them.")
    var resume: String?

    func validate() throws {
        if continueLatest, resume != nil { throw ValidationError("Use --continue or --resume, not both.") }
    }

    private var limits: RunLimits {
        RunLimits(maximumTurns: Swift.max(1, maxTurns), compactAtTokens: compactAt > 0 ? compactAt : nil)
    }

    private var session: SessionChoice {
        if let resume { return .named(resume) }
        return continueLatest ? .latest : .new
    }

    func run() async throws {
        if budgets {
            FileHandle.standardOutput.write(Data(try Budget.reportJSON()))
            return
        }
        let resolved: ResolvedModel
        do { resolved = try resolveModel(provider: provider, model: model) } catch { fail("ask: \(error)", code: 78) }
        if let prompt {
            await runPrompt(prompt, model: resolved, limits: limits, session: session)
            return
        }
        await runInteractive(model: resolved, limits: limits, session: session)
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
