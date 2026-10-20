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
        subcommands: [
            Login.self, Logout.self, ModelsCommand.self, ConnectionsCommand.self, Sessions.self, ConfigCommand.self,
            TrustCommand.self,
            UntrustCommand.self
        ])

    @Flag(help: "Print the four performance budgets as JSON and exit. Read by Scripts/measure-budgets.py.")
    var budgets = false

    @Option(
        name: [.short, .customLong("print")],
        help: "Run one prompt with the tools, stream the answer to standard output, and exit.")
    var prompt: String?

    @Option(help: "The model to use. Default: config.json, else the provider's default model.")
    var model: String?

    @Option(
        help:
            "The connection: a registered name, built-in anthropic/codex, or providers.json entry. Default: config.json, else the file's default."
    )
    var provider: String?

    @Option(help: "The most model requests one prompt may make before ask stops it. Default: config.json, else 100.")
    var maxTurns: Int?

    @Option(
        help: ArgumentHelp(
            "Compact the conversation once its context reaches this many tokens; 0 only when the window is full. "
                + "Default: config.json, else 150000.",
            valueName: "tokens"))
    var compactAt: Int?

    @Flag(
        name: .customLong("no-sandbox"),
        help: "Turn off ask's protections for this run: its own files and your secret stores become reachable.")
    var noSandbox = false

    @Flag(name: .customLong("self-check"), help: .hidden)
    var selfCheck = false

    @Option(name: .customLong("reloaded-from"), help: .hidden)
    var reloadedFrom: String?

    @Option(name: .customLong("reload-started"), help: .hidden)
    var reloadStarted: Int?

    @Flag(name: [.short, .customLong("continue")], help: "Continue the session written last in this project.")
    var continueLatest = false

    @Option(
        name: [.short, .customLong("resume")],
        help: "Resume a session by name, unique name prefix, or path. `ask sessions` lists them.")
    var resume: String?

    func validate() throws {
        if continueLatest, resume != nil { throw ValidationError("Use --continue or --resume, not both.") }
        if let maxTurns, maxTurns < 1 { throw ValidationError("--max-turns must be at least 1.") }
        if let compactAt, compactAt < 0 { throw ValidationError("--compact-at must be 0 or more.") }
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
        var startupNotices: [String] = []
        let restored =
            selfCheck
            ? nil
            : session.open(
                in: SessionDirectory(project: FileManager.default.currentDirectoryPath),
                note: { startupNotices.append($0) })
        var source = ConfigurationSource(
            workingDirectory: FileManager.default.currentDirectoryPath,
            flags: .init(
                model: model, provider: provider, maxTurns: maxTurns, compactAt: compactAt, noSandbox: noSandbox))
        source.resumedDestination = restored?.destination
        let settings: RunSettings
        do { settings = try await source.load(allowNetwork: !selfCheck) } catch {
            fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error))
        }
        if selfCheck {
            checkSelf(settings)
            return
        }
        let reloaded = reloadedFrom.map { ReloadNotice(from: $0, startedMilliseconds: reloadStarted ?? 0) }
        if let prompt {
            await runPrompt(
                prompt, source: source, settings: settings, resumed: restored, startupNotices: startupNotices)
            return
        }
        await runInteractive(
            source: source, settings: settings, resumed: restored, startupNotices: startupNotices, reloaded: reloaded)
    }
}

/// `ask login`: sign in to a provider. Claude by default.
struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sign in to a provider.",
        discussion: "claude, codex: a subscription. spettro, mistral-vibe: a browser sign-in that issues an API key.")

    @Argument(help: "Which sign-in to run.") var provider: LoginTarget = .claude
    @Flag(help: "For codex: sign in with a code typed at a link, on a machine with no browser.") var device = false
    @Option(help: "Register a separate named codex or claude connection, without replacing the default account.")
    var name: String?
    @Flag(help: "Authorize replacing the remote account bound to this named connection.") var replaceAccount = false

    func run() async throws {
        let connection: ConnectionRecord?
        if let name {
            let kind: ConnectionKind
            switch provider {
                case .codex: kind = .codex
                case .claude: kind = .anthropic
                default: throw ValidationError("Named sign-ins currently support codex and claude.")
            }
            connection = try NamedConnections.registry()
                .register(name: name, provider: kind, reserved: NamedConnections.reserved())
        } else {
            guard !replaceAccount else { throw ValidationError("--replace-account requires --name.") }
            connection = nil
        }
        let file = NamedConnections.file(for: connection)
        switch provider {
            case .claude: await claudeLogin(file: file, connection: connection)
            case .codex:
                await codexLogin(device: device, file: file, connection: connection, replaceAccount: replaceAccount)
            case .spettro:
                let flow: SpettroSignIn
                do {
                    let base = ProcessInfo.processInfo.environment["SPETTRO_API_URL"] ?? SpettroSignIn.defaultBase
                    flow = try SpettroSignIn(transport: URLSessionTransport(), base: base)
                } catch { fail("ask: sign-in failed: \(error)", code: 77) }
                await browserLogin(flow, keyName: SpettroSignIn.provider, file: file)
            case .mistralVibe:
                await browserLogin(
                    VibeSignIn(transport: URLSessionTransport()), keyName: VibeSignIn.provider, file: file)
        }
    }

    private func claudeLogin(file: CredentialFile, connection: ConnectionRecord?) async {
        let pending = PendingSignIn.begin()
        print("Open this URL and sign in:\n\n  \(pending.url)\n\nThen paste the code it shows (code#state):")
        guard let pasted = readLine(strippingNewline: true) else { fail("ask: no code entered.", code: 66) }
        do {
            let credentials = try await ClaudeAuthClient(transport: URLSessionTransport())
                .complete(pending, pasted: pasted, now: Date().timeIntervalSince1970)
            if let connection {
                try NamedConnections.registry().saveClaude(credentials, for: connection, replaceAccount: replaceAccount)
            } else {
                try file.saveClaude(credentials)
            }
            print("Signed in\(credentials.accountEmail.map { " as \($0)" } ?? ""). Credentials: \(file.url.path)")
        } catch {
            fail("ask: sign-in failed: \(error)", code: 77)
        }
    }
}

/// `ask logout`: forget stored credentials, one provider's or all.
struct Logout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget stored credentials.")

    @Argument(help: "Forget only this sign-in. Default: all of them.") var provider: String?

    func run() throws {
        let file = CredentialFile.standard()
        do {
            if let name = provider {
                if let target = LoginTarget(rawValue: name) {
                    switch target {
                        case .claude: try file.removeClaude()
                        case .codex: try file.removeCodex()
                        default: try target.keyName.map { try file.removeKey(for: $0) }
                    }
                } else {
                    try NamedConnections.registry().signOut(NamedConnections.named(name))
                }
            } else {
                try file.remove()
                let listing = try NamedConnections.registry().list()
                NamedConnections.report(listing.notices)
                for record in listing.records { try NamedConnections.registry().signOut(record) }
                if !listing.notices.isEmpty {
                    fail(
                        "ask: readable connections were signed out, but unreadable registrations could not be changed; see the notices above",
                        code: 78)
                }
            }
        } catch { fail("ask: \(error)", code: 78) }
        print("Signed out.")
    }
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
