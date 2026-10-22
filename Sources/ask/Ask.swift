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

    @Option(
        help:
            "Requested thinking: \(ThinkingLevel.choices). Unset preserves provider defaults; unsupported controls are not remapped."
    )
    var thinking: String?

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

    @Option(
        help: ArgumentHelp(
            "How far commands may reach the network: none, localhost or any. Replaces config.json's sandbox.network.",
            valueName: "level"))
    var network: String?

    @Option(
        help: ArgumentHelp(
            "Where commands and tools may write: workspace (this directory), anywhere, or one directory. "
                + "Replaces config.json's sandbox.write.",
            valueName: "scope"))
    var write: String?

    @Option(
        help: ArgumentHelp(
            "Where commands and tools may read: workspace (this directory, the system and developer tools), "
                + "anywhere, or one directory. Replaces config.json's sandbox.read.",
            valueName: "scope"))
    var read: String?

    @Flag(name: .customLong("self-check"), help: .hidden)
    var selfCheck = false

    @Option(name: .customLong("reloaded-from"), help: .hidden)
    var reloadedFrom: String?

    @Option(name: .customLong("reload-started"), help: .hidden)
    var reloadStarted: Int?

    @Option(name: .customLong("selected-provider"), help: .hidden)
    var selectedProvider: String?

    @Option(name: .customLong("selected-model"), help: .hidden)
    var selectedModel: String?

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
        if let thinking, ThinkingLevel(rawValue: thinking) == nil {
            throw ValidationError("--thinking must be one of: \(ThinkingLevel.choices).")
        }
        if noSandbox, network != nil || write != nil || read != nil {
            throw ValidationError("--no-sandbox turns the sandbox off; --network, --write and --read need it on.")
        }
        if let network, SandboxPolicy.Network(named: network) == nil {
            throw ValidationError("--network must be none, localhost or any.")
        }
        for (flag, value) in [("--write", write), ("--read", read)] {
            if let value, !["workspace", "anywhere"].contains(value), !value.hasPrefix("/"), !value.hasPrefix("~/") {
                throw ValidationError(
                    "\(flag) must be workspace, anywhere, or an absolute path (or one starting with ~/).")
            }
        }
        if (selectedProvider == nil) != (selectedModel == nil) {
            throw ValidationError("--selected-provider and --selected-model go together.")
        }
    }

    /// `--write` or `--read` as a setting.
    private static func scope(_ value: String?) -> PathSetting? {
        switch value {
            case nil: nil
            case "workspace": .workspace
            case "anywhere": .anywhere
            case let path?: .paths([path])
        }
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
                model: model, provider: provider, maxTurns: maxTurns, compactAt: compactAt,
                thinking: thinking.flatMap(ThinkingLevel.init(rawValue:)), noSandbox: noSandbox,
                network: network.flatMap(SandboxPolicy.Network.init(named:)), write: Self.scope(write),
                read: Self.scope(read),
                selected: selectedProvider.flatMap { provider in
                    selectedModel.map { ModelSelection(provider: provider, model: $0) }
                }))
        source = source.resuming(restored)
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

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
