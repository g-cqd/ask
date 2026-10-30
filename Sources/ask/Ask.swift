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
            TrustCommand.self, SkillsCommand.self,
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
            "The connection: a registered name, built-in anthropic/codex/agy/apple, or providers.json entry. Default: config.json, else the file's default, else an account you are signed in to, else Apple's on-device model."
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
            "Compact the conversation once its context reaches this share of the model's window (75%) or this many tokens; "
                + "0 only when the window is full. Default: config.json, else 75%.",
            valueName: "share-or-tokens"))
    var compactAt: String?

    @Flag(
        name: .customLong("no-sandbox"),
        help: "Turn off ask's protections for this run: its own files and your secret stores become reachable.")
    var noSandbox = false

    @Flag(help: "Run every tool call without asking first, for this run (roadmap 0134).")
    var yes = false

    @Flag(
        name: .customLong("ask-always"),
        help: "Ask before every call that changes things, even what config.json allows.")
    var askAlways = false

    @Option(
        help: ArgumentHelp(
            "How far commands may reach the network: none, localhost or any. Replaces config.json's sandbox.network.",
            valueName: "level"))
    var network: String?

    @Option(
        help: ArgumentHelp(
            "Where commands and tools may write: workspace (this directory), anywhere, or a directory; repeat it "
                + "for several directories. Replaces config.json's sandbox.write.",
            valueName: "scope"))
    var write: [String] = []

    @Option(
        help: ArgumentHelp(
            "Where commands and tools may read: workspace (this directory, the system and developer tools), "
                + "anywhere, or a directory; repeat it for several directories. Replaces config.json's sandbox.read.",
            valueName: "scope"))
    var read: [String] = []

    @Flag(
        name: [.short, .customLong("verbose")],
        help:
            "Show details a regular run leaves out: the sandbox in force, the files read, where the model came from. /verbose toggles it."
    )
    var verbose = false

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
        name: [.short, .customLong("resume")], defaultAsFlag: "", parsing: .next,
        help: "Choose a session, or resume directly with --resume NAME, PREFIX or PATH.")
    var resume: String? = nil

    func validate() throws {
        if continueLatest, resume != nil { throw ValidationError("Use --continue or --resume, not both.") }
        if resume == "", prompt != nil {
            throw ValidationError("With --prompt, --resume needs a session name or path.")
        }
        if let maxTurns, maxTurns < 1 { throw ValidationError("--max-turns must be at least 1.") }
        if let compactAt, CompactionThreshold(parsing: compactAt) == nil {
            throw ValidationError("--compact-at must be \(CompactionThreshold.expected).")
        }
        if let thinking, ThinkingLevel(rawValue: thinking) == nil {
            throw ValidationError("--thinking must be one of: \(ThinkingLevel.choices).")
        }
        if yes, askAlways { throw ValidationError("--yes and --ask-always say opposite things; give one.") }
        if noSandbox, network != nil || !write.isEmpty || !read.isEmpty {
            throw ValidationError("--no-sandbox turns the sandbox off; --network, --write and --read need it on.")
        }
        if let network, SandboxPolicy.Network(named: network) == nil {
            throw ValidationError("--network must be none, localhost or any.")
        }
        try Self.validateScopes(write: write, read: read)
        if (selectedProvider == nil) != (selectedModel == nil) {
            throw ValidationError("--selected-provider and --selected-model go together.")
        }
    }

    /// `--write` and `--read`: each value is a keyword or an absolute path, and keywords stand alone.
    private static func validateScopes(write: [String], read: [String]) throws {
        for (flag, values) in [("--write", write), ("--read", read)] {
            for value in values
            where !["workspace", "anywhere"].contains(value) && !value.hasPrefix("/") && !value.hasPrefix("~/") {
                throw ValidationError(
                    "\(flag) must be workspace, anywhere, or an absolute path (or one starting with ~/).")
            }
            if values.count > 1, values.contains(where: { ["workspace", "anywhere"].contains($0) }) {
                throw ValidationError("\(flag) given several times takes directories only, not workspace or anywhere.")
            }
        }
    }

    /// What this command line asks for, as plain values (see ``LaunchRequest``).
    private var request: LaunchRequest {
        LaunchRequest(
            budgets: budgets, prompt: prompt, model: model, provider: provider, thinking: thinking, maxTurns: maxTurns,
            compactAt: compactAt, noSandbox: noSandbox, yes: yes, askAlways: askAlways, network: network,
            write: write, read: read,
            selfCheck: selfCheck, verbose: verbose, reloadedFrom: reloadedFrom, reloadStarted: reloadStarted,
            selectedProvider: selectedProvider, selectedModel: selectedModel, continueLatest: continueLatest,
            resume: resume)
    }

    func run() async throws { try await request.run() }

    /// A bare `ask` has nothing to parse: every option is its default, so the request is made directly and
    /// ArgumentParser's reflection over the command tree is never paid for (ADR-0065, roadmap 0054).
    /// Anything else goes through the parser exactly as before.
    static func main() async {
        guard CommandLine.arguments.count == 1 else { return await main(nil) }
        do { try await LaunchRequest().run() } catch { exit(withError: error) }
    }
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(code)
}
