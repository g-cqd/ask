internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Where a run's settings come from, and how to read them again: the loader, the command-line flags that stay
/// the highest layer across reloads, and `providers.json`.
struct ConfigurationSource: Sendable {
    let loader: ConfigurationLoader
    let providersPath: String
    var flags: Flags
    let environment: [String: String]
    /// A resumed session pins its destination unless the launch flags explicitly override it.
    var resumedDestination: SessionDestination?
    /// The directory ask was started in: what a `workspace` write scope means.
    let workspace: String
    /// The strict sandbox the session being continued recorded: a narrowing layer below the flags.
    var sessionSandbox: SandboxSection?

    /// The flags the user gave; nil for one not given.
    struct Flags: Sendable {
        var model: String?
        var provider: String?
        var maxTurns: Int?
        var compactAt: CompactionThreshold?
        var thinking: ThinkingLevel?
        /// `--no-sandbox`: the user turned ask's protections off for this run.
        var noSandbox = false
        /// `--yes` or `--ask-always`: over the `approvals` section (roadmap 0134).
        var approvalFlag: ApprovalPolicy.Flag?
        /// `--allow`: tool calls run without asking for this run (roadmap 0156).
        var approvalAllow: [String] = []
        /// `--ask` other than `all`: tool calls asked about for this run even when the files allow them (roadmap 0154).
        var approvalAsk: [String] = []
        /// `--verbose`: details are shown (ADR-0119).
        var verbose = false
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
            if let compactAt { arguments += ["--compact-at", compactAt.description] }
            if let thinking { arguments += ["--thinking", thinking.rawValue] }
            if noSandbox { arguments.append("--no-sandbox") }
            switch approvalFlag {
                case .yes?: arguments.append("--yes")
                case .askAlways?: arguments += ["--ask", "all"]
                case nil: break
            }
            for name in approvalAllow { arguments += ["--allow", name] }
            for name in approvalAsk { arguments += ["--ask", name] }
            if verbose { arguments.append("--verbose") }
            if let network { arguments += ["--network", network.description] }
            for (flag, setting) in [("--write", write), ("--read", read)] {
                switch setting {
                    case .anywhere?: arguments += [flag, "anywhere"]
                    case .workspace?: arguments += [flag, "workspace"]
                    case .paths(let paths)?: for path in paths { arguments += [flag, path] }
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
    init(workingDirectory: String, flags: Flags, environment: [String: String] = LaunchEnvironment.values) {
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
                    denyRead: section.denyRead.map { SandboxSection.expand($0, home: home) }, workspace: workspace,
                    allowWrite: section.allowWrite.map {
                        SandboxSection.expandWrite($0, home: home, workspace: workspace)
                    },
                    otherSecrets: (OtherAgentsSecrets.directories, OtherAgentsSecrets.files))
            }
            .reduce(SandboxPolicy.unrestricted) { $0.intersecting($1) }
        policy.network = section.network ?? .any
        let home = homes.last ?? NSHomeDirectory()
        policy.write = section.writeScope(workspace: workspace, home: home)
        // Kept to the workspace, builds still write their caches (owner, 2026-10-29), in every home.
        if case .roots(let roots) = policy.write {
            let caches = homes.flatMap(SandboxPolicy.developerWrites(home:))
                .map { CanonicalPath.of($0, relativeTo: "/") ?? $0 }
            policy.write = .roots(roots + caches.filter { !roots.contains($0) })
        }
        policy.read = section.readScope(
            workspace: workspace, home: home,
            // Every home's: the account's holds the toolchains, $HOME the configuration a command's `~` finds.
            always: homes.flatMap(Self.developerReads(home:))
                + section.allowRead.map { SandboxSection.expand($0, home: home) })
        return policy
    }

    /// This source for continuing `session`, or none: its recorded destination is pinned unless the user names
    /// another, and its recorded strict sandbox becomes a layer below the flags.
    func resuming(_ session: SessionRecorder?) -> ConfigurationSource {
        var next = self
        next.sessionSandbox = session?.sandbox
        next.resumedDestination = session?.destination
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
            network: flags.network, write: flags.write, read: flags.read, thinking: flags.thinking)
        var details: [String] = []
        // Before anything reads a credential: the choice decides where they are read from.
        result.notices += CredentialPlacement.apply(result.configuration.credentials.value, environment: environment)
        if let record = sessionSandbox, !flags.noSandbox {
            let before = result.configuration.sandbox
            result.configuration = result.configuration.applying(
                session: record, flaggedNetwork: flags.network != nil, flaggedWrite: flags.write != nil,
                flaggedRead: flags.read != nil)
            if result.configuration.sandbox != before {
                details.append("Keeping this session's sandbox (\(record)); --network and --write change it.")
            }
        }
        if let selected = flags.selected {
            result.configuration = result.configuration.applying(
                selectedProvider: selected.provider, model: selected.model, command: "/model")
        }
        let providers = try ProviderSettings.load(from: providersPath)
        // A flag or a /model choice is the user's say; otherwise a resumed session stays where it was sent (ADR-0048).
        let pinned = flags.provider == nil && flags.selected == nil ? resumedDestination : nil
        let selected = try pinned.map { try SessionRouting.pinnedProvider($0, environment: environment) }
        let discovered = try await resolveWithinScope(
            result.configuration, providers: providers, provider: selected ?? result.configuration.provider.value,
            // A /model choice, then --model, then the resumed session's model, then the configuration.
            model: flags.selected?.model ?? flags.model ?? pinned?.model ?? result.configuration.model.value,
            allowNetwork: allowNetwork,
            choice: ModelDiscovery.Choice(
                providerIsFlagged: flags.provider != nil || flags.selected != nil,
                modelIsFlagged: flags.model != nil || flags.selected != nil,
                thinking: result.configuration.thinking.value))
        if let level = discovered.model.thinking, let alias = discovered.model.alias,
            let connection = discovered.model.connection
        {
            result.configuration = result.configuration.applying(
                aliasThinking: level, alias: "\(connection.name)/\(alias)")
        }
        let thinking = try ThinkingDiscovery.resolve(
            result.configuration.thinking.value, model: discovered.model, environment: environment)
        // The `provider` network level lets commands reach this run's provider through ask's proxy (roadmap 0021); a later /model
        // resolves again and moves it.
        ProviderAccess.allow(
            Set(
                [ProviderServer.url(for: thinking.model, environment: environment)]
                    .compactMap { url in
                        url.flatMap { ProxyRequest.Target(url: $0.absoluteString) }
                    }))
        let commandEnvironment = CommandEnvironment(providers: providers, configuration: result.configuration)
        // Everything that needed the credentials has read them: the snapshot keeps them, ask's own process does not (ADR-0113).
        LaunchEnvironment.conceal(commandEnvironment)
        let sandbox: SandboxPolicy = flags.noSandbox ? .unrestricted : protections(result.configuration.sandbox.value)
        return RunSettings(
            configuration: result.configuration, model: thinking.model, sandbox: sandbox, applied: result.applied,
            notices: result.notices + discovered.notices + thinking.notices
                + [JobTable.unusableShellNotice(commandEnvironment, environment: environment)].compactMap { $0 },
            workspace: workspace, thinking: thinking.control, thinkingStatus: thinking.status,
            thinkingPending: thinking.pending,
            commandEnvironment: commandEnvironment,
            details: details + discovered.details
                + (pinned.map { ["Resuming recorded destination \(selected ?? $0.name)/\($0.model)."] } ?? [])
                + (flags.noSandbox
                    ? ["The sandbox is off (--no-sandbox): ask's own files and your secret stores are not protected."]
                    : []),
            verbose: flags.verbose, approvalFlag: flags.approvalFlag, approvalAllow: flags.approvalAllow,
            approvalAsk: flags.approvalAsk)
    }
}
