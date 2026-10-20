internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Where a run's settings come from, and how to read them again: the loader, the command-line flags that stay
/// the highest layer across reloads, and `providers.json`.
struct ConfigurationSource: Sendable {
    let loader: ConfigurationLoader
    let providersPath: String
    var flags: Flags
    let environment: [String: String]
    /// The directory ask was started in: what a `workspace` write scope means.
    let workspace: String
    /// The strict sandbox the session being continued recorded: a narrowing layer below the flags.
    var sessionSandbox: SandboxSection?

    /// The flags the user gave; nil for one not given.
    struct Flags: Sendable {
        var model: String?
        var provider: String?
        var maxTurns: Int?
        var compactAt: Int?
        /// `--no-sandbox`: the user turned ask's protections off for this run.
        var noSandbox = false
        /// `--network`: how far the network reaches, replacing what the files say.
        var network: SandboxPolicy.Network?
        /// `--write`: where writing is allowed, replacing what the files say.
        var write: PathSetting?
        /// `--read`: where reading is allowed, replacing what the files say.
        var read: PathSetting?
        /// The model chosen with `/model`; above every other layer, for this process and the ones a reload starts.
        var selected: ModelSelection?

        /// The flags as they were given, to pass to a replacement process.
        var arguments: [String] {
            var arguments: [String] = []
            if let model { arguments += ["--model", model] }
            if let provider { arguments += ["--provider", provider] }
            if let maxTurns { arguments += ["--max-turns", String(maxTurns)] }
            if let compactAt { arguments += ["--compact-at", String(compactAt)] }
            if noSandbox { arguments.append("--no-sandbox") }
            if let network { arguments += ["--network", network.description] }
            for (flag, setting) in [("--write", write), ("--read", read)] {
                switch setting {
                    case .anywhere?: arguments += [flag, "anywhere"]
                    case .workspace?: arguments += [flag, "workspace"]
                    case .paths(let paths)?: arguments += [flag] + paths.prefix(1)
                    case nil: break
                }
            }
            if let selected {
                arguments += ["--selected-provider", selected.provider, "--selected-model", selected.model]
            }
            return arguments
        }
    }

    /// The source for the project at `workingDirectory`.
    init(workingDirectory: String, flags: Flags, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let directory = askConfigDirectory(environment: environment)
        loader = ConfigurationLoader(project: workingDirectory, configDirectory: directory, environment: environment)
        providersPath = directory + "/providers.json"
        self.flags = flags
        self.environment = environment
        self.workspace = workingDirectory
    }

    /// ask's default protections over every home directory a tool could mean by `~`: the account's, and `$HOME` when
    /// it names another. `NSHomeDirectory()` ignores `$HOME`, while a command's `~` follows it, so protecting one
    /// would leave the other's secret stores open.
    private func protections(_ section: SandboxSection) -> SandboxPolicy {
        var homes = [NSHomeDirectory()]
        if let fromEnvironment = environment["HOME"], fromEnvironment.hasPrefix("/"), !homes.contains(fromEnvironment) {
            homes.append(fromEnvironment)
        }
        // The strict modes (roadmap 0042): `~/` in a write path means the shell's home, the one commands see.
        var policy =
            homes.map { home in
                SandboxPolicy.standard(
                    home: home, configDirectory: askConfigDirectory(environment: environment),
                    stateDirectory: SessionDirectory.stateRoot(environment: environment, home: home),
                    allowRead: section.allowRead.map { SandboxSection.expand($0, home: home) },
                    denyRead: section.denyRead.map { SandboxSection.expand($0, home: home) })
            }
            .reduce(SandboxPolicy.unrestricted) { $0.intersecting($1) }
        policy.network = section.network ?? .any
        let home = homes.last ?? NSHomeDirectory()
        policy.write = section.writeScope(workspace: workspace, home: home)
        policy.read = section.readScope(
            workspace: workspace, home: home,
            // Every home's: the account's holds the toolchains, $HOME the configuration a command's `~` finds.
            always: homes.flatMap(Self.developerReads(home:))
                + section.allowRead.map { SandboxSection.expand($0, home: home) })
        return policy
    }

    /// This source for continuing `session`: its recorded strict sandbox becomes a layer below the flags, or none.
    func resuming(_ session: SessionRecorder?) -> ConfigurationSource {
        var next = self
        next.sessionSandbox = session?.sandbox
        return next
    }

    /// The source for the current directory with no flags: what the configuration commands read.
    static var here: ConfigurationSource {
        ConfigurationSource(workingDirectory: FileManager.default.currentDirectoryPath, flags: Flags())
    }

    /// Reads every layer and resolves the model, all or nothing.
    /// - Throws: a ``ConfigurationError`` or a ``ProviderSettingsError``, naming the file.
    func load(allowNetwork: Bool = true) async throws -> RunSettings {
        var result = try loader.load(
            model: flags.model, provider: flags.provider, maxTurns: flags.maxTurns, compactAt: flags.compactAt,
            network: flags.network, write: flags.write, read: flags.read)
        if let record = sessionSandbox, !flags.noSandbox {
            let before = result.configuration.sandbox
            result.configuration = result.configuration.applying(
                session: record, flaggedNetwork: flags.network != nil, flaggedWrite: flags.write != nil,
                flaggedRead: flags.read != nil)
            if result.configuration.sandbox != before {
                result.notices.append(
                    "Keeping this session's sandbox (\(record)); --network and --write change it.")
            }
        }
        if let selected = flags.selected {
            result.configuration = result.configuration.applying(
                selectedProvider: selected.provider, model: selected.model, command: "/model")
        }
        let providers = try ProviderSettings.load(from: providersPath)
        let discovered = try await ModelDiscovery.resolve(
            providers: providers, provider: result.configuration.provider.value,
            model: result.configuration.model.value,
            environment: environment, allowNetwork: allowNetwork)
        let sandbox: SandboxPolicy = flags.noSandbox ? .unrestricted : protections(result.configuration.sandbox.value)
        return RunSettings(
            configuration: result.configuration, model: discovered.model, sandbox: sandbox, applied: result.applied,
            notices: result.notices + discovered.notices
                + (flags.noSandbox
                    ? ["The sandbox is off (--no-sandbox): ask's own files and your secret stores are not protected."]
                    : []),
            workspace: workspace)
    }
}
