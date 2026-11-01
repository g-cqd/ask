internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

// Reading the layers and resolving the model for a run; apart from ConfigurationSource.swift to keep the
// type body under 200 lines.
extension ConfigurationSource {
    /// Every layer read, the credentials placed as they say, then the resumed session's sandbox and the /model choice applied;
    /// with a detail for a session sandbox that was kept.
    func layers() throws -> (result: ConfigurationLoader.Result, details: [String]) {
        var result = try loader.load(
            model: flags.model,
            provider: flags.provider,
            maxTurns: flags.maxTurns,
            compactAt: flags.compactAt,
            network: flags.network,
            write: flags.write,
            read: flags.read,
            thinking: flags.thinking
        )
        var details: [String] = []
        // Before anything reads a credential: the choice decides where they are read from.
        result.notices += CredentialPlacement.apply(result.configuration.credentials.value, environment: environment)
        if let record = sessionSandbox, !flags.noSandbox {
            let before = result.configuration.sandbox
            result.configuration = result.configuration.applying(
                session: record,
                flaggedNetwork: flags.network != nil,
                flaggedWrite: flags.write != nil,
                flaggedRead: flags.read != nil
            )
            if result.configuration.sandbox != before {
                details.append("Keeping this session's sandbox (\(record)); --network and --write change it.")
            }
        }
        if let selected = flags.selected {
            result.configuration = result.configuration.applying(
                selectedProvider: selected.provider,
                model: selected.model,
                command: "/model"
            )
        }
        return (result, details)
    }

    /// Reads every layer and resolves the model, all or nothing.
    /// - Throws: a ``ConfigurationError`` or a ``ProviderSettingsError``, naming the file.
    func load(allowNetwork: Bool = true) async throws -> RunSettings {
        var (result, details) = try layers()
        let providers = try ProviderSettings.load(from: providersPath)
        // A flag or a /model choice is the user's say; otherwise a resumed session stays where it was sent (ADR-0048).
        let pinned = flags.provider == nil && flags.selected == nil ? resumedDestination : nil
        let selected = try pinned.map { try SessionRouting.pinnedProvider($0, environment: environment) }
        let discovered = try await resolveWithinScope(
            result.configuration,
            providers: providers,
            provider: selected ?? result.configuration.provider.value,
            // A /model choice, then --model, then the resumed session's model, then the configuration.
            model: flags.selected?.model ?? flags.model ?? pinned?.model ?? result.configuration.model.value,
            allowNetwork: allowNetwork,
            choice: ModelDiscovery.Choice(
                providerIsFlagged: flags.provider != nil || flags.selected != nil,
                modelIsFlagged: flags.model != nil || flags.selected != nil,
                thinking: result.configuration.thinking.value
            )
        )
        if let level = discovered.model.thinking, let alias = discovered.model.alias,
            let connection = discovered.model.connection
        {
            result.configuration = result.configuration.applying(
                aliasThinking: level,
                alias: "\(connection.name)/\(alias)"
            )
        }
        let thinking = try ThinkingDiscovery.resolve(
            result.configuration.thinking.value,
            model: discovered.model,
            environment: environment
        )
        allowProxy(to: thinking.model)
        let commandEnvironment = CommandEnvironment(providers: providers, configuration: result.configuration)
        // Everything that needed the credentials has read them: the snapshot keeps them, ask's own process does not (ADR-0113).
        LaunchEnvironment.conceal(commandEnvironment)
        let sandbox: SandboxPolicy = flags.noSandbox ? .unrestricted : protections(result.configuration.sandbox.value)
        return RunSettings(
            configuration: result.configuration,
            model: thinking.model,
            sandbox: sandbox,
            applied: result.applied,
            notices: result.notices + discovered.notices + thinking.notices
                + [JobTable.unusableShellNotice(commandEnvironment, environment: environment)].compactMap { $0 },
            workspace: workspace,
            thinking: thinking.control,
            thinkingStatus: thinking.status,
            thinkingPending: thinking.pending,
            commandEnvironment: commandEnvironment,
            details: details + discovered.details
                + (pinned.map { ["Resuming recorded destination \(selected ?? $0.name)/\($0.model)."] } ?? [])
                + (flags.noSandbox
                    ? ["The sandbox is off (--no-sandbox): ask's own files and your secret stores are not protected."]
                    : []),
            verbose: flags.verbose,
            approvalFlag: flags.approvalFlag,
            approvalAllow: flags.approvalAllow,
            approvalAsk: flags.approvalAsk
        )
    }

    private func allowProxy(to model: ResolvedModel) {
        // The `provider` network level lets commands reach this run's provider through ask's proxy (roadmap 0021); a later /model
        // resolves again and moves it.
        ProviderAccess.allow(
            Set(
                [ProviderServer.url(for: model, environment: environment)]
                    .compactMap { url in
                        url.flatMap { ProxyRequest.Target(url: $0.absoluteString) }
                    }
            )
        )
    }
}
