internal import AskAI
internal import AskAgentCore
internal import AskApple
internal import Foundation

/// The CLI's binding of discovery to the current connection; provider behavior stays in AskAI.
enum ModelDiscovery {
    static func codex(environment: [String: String], connection: ConnectionRecord? = nil) -> CodexModelCatalog {
        let credentials = NamedConnections.file(for: connection, environment: environment)
        return CodexModelCatalog(
            credentials: credentials,
            cache: ModelCatalogFile(
                url: credentials.url.deletingLastPathComponent().appending(path: "models-codex.json")
            ),
            transport: URLSessionTransport(),
            connection: connection
        )
    }

    /// The Antigravity account's list, kept in `models-agy.json` beside the credentials.
    static func agy(environment: [String: String] = LaunchEnvironment.values) -> AgyModelCatalog {
        let credentials = NamedConnections.file(for: nil, environment: environment)
        let transport = URLSessionTransport()
        return AgyModelCatalog(
            credentials: credentials,
            cache: ModelCatalogFile(
                url: credentials.url.deletingLastPathComponent().appending(path: "models-agy.json")
            ),
            cloud: AgyCloudClient(transport: transport),
            access: makeAgyAccess(transport: transport)
        )
    }

    /// Resolve normally first; only a missing Codex default requires discovery. Explicit model ids never need a network.
    static func resolve(
        providers: ProviderSettings,
        provider: String?,
        model: String?,
        environment: [String: String],
        allowNetwork: Bool,
        choice: Choice = Choice()
    ) async throws -> (model: ResolvedModel, notices: [String], details: [String]) {
        let found = try await resolveAll(
            providers: providers,
            provider: provider,
            model: model,
            environment: environment,
            allowNetwork: allowNetwork,
            choice: choice
        )
        return (
            found.model, found.notices.filter { !$0.hasPrefix(detailMark) },
            found.notices.filter { $0.hasPrefix(detailMark) }.map { String($0.dropFirst(detailMark.count)) }
        )
    }

    /// Marks a line that says what ask decided by itself and not what the person needs to act on: ``resolve`` keeps those apart as details
    /// (ADR-0119), so the helpers below can go on returning one list.
    static let detailMark = "\u{1}"

    static func detail(_ text: String) -> String { detailMark + text }

    private static func resolveAll(
        providers: ProviderSettings,
        provider: String?,
        model: String?,
        environment: [String: String],
        allowNetwork: Bool,
        choice: Choice
    ) async throws -> (model: ResolvedModel, notices: [String]) {
        var (provider, model, notices) = qualified(
            provider,
            model,
            providers: providers,
            environment: environment,
            choice: choice
        )
        let picked = automatic(provider, providers: providers, environment: environment)
        provider = picked.provider
        notices += picked.notices
        let selected = providers.selectedProvider(provider)
        if selected == CopilotProtocol.name {
            return try await resolveCopilot(
                providers,
                model: model,
                environment: environment,
                allowNetwork: allowNetwork,
                notices: notices
            )
        }
        let (connection, found) = try registered(selected, environment: environment)
        notices += found
        let (aliases, aliasNotices) = try connectionAliases(connection, model: model, environment: environment)
        notices += aliasNotices
        let resolve: ([CatalogModel]) throws -> ResolvedModel = { catalog in
            try providers.resolve(
                provider: provider,
                model: model,
                environment: environment,
                catalog: catalog,
                connection: connection,
                aliases: aliases,
                storedKeys: { () throws(CredentialFileError) in
                    try CredentialFile.standard(environment: environment).loadKeys().mapValues(\.key)
                }
            )
        }
        let initial: ResolvedModel
        do { initial = try resolve([]) } catch ProviderSettingsError.noModel(let name)
            where name == ProviderSettings.codex
        {
            return try await fromCodexCatalog(
                connection,
                environment: environment,
                allowNetwork: allowNetwork,
                resolve: resolve,
                notices: notices
            )
        }
        if initial.provider == .anthropic {
            return withAnthropicLimits(initial, environment: environment, notices: notices)
        }
        if initial.provider == .apple { return withAppleLimits(initial, notices: notices) }
        if initial.provider == .agy { return try withAgyLimits(initial, resolve: resolve, notices: notices) }
        guard initial.provider == .codex else {
            return try withListedLimits(initial, environment: environment, resolve: resolve, notices: notices)
        }
        return withCodexLimits(initial, environment: environment, resolve: resolve, notices: notices)
    }

    /// The on-device model with the window Apple documents for it. The system is not asked at launch: asking loads the framework's model stack,
    /// 6 MB of idle memory for a run that may never use it (ADR-0116). The first request reports a model that cannot answer.
    /// The model a Codex connection names without a version, picked from the account's catalog: fetched when the network is
    /// allowed, else the cached one.
    private static func fromCodexCatalog(
        _ connection: ConnectionRecord?,
        environment: [String: String],
        allowNetwork: Bool,
        resolve: ([CatalogModel]) throws -> ResolvedModel,
        notices: [String]
    ) async throws -> (model: ResolvedModel, notices: [String]) {
        let catalog = codex(environment: environment, connection: connection)
        let snapshot: CatalogSnapshot
        if allowNetwork {
            snapshot = try await catalog.models(now: Date().timeIntervalSince1970)
        } else {
            guard let cached = try catalog.cached(now: Date().timeIntervalSince1970) else {
                throw ProviderSettingsError.noModel(provider: ProviderSettings.codex)
            }
            snapshot = cached
        }
        let chosen = try resolve(
            ModelUsefulness.shown(snapshot.models, onlyUseful: ModelFilter.onlyUseful(environment: environment))
        )
        return (
            chosen,
            notices + snapshot.notices + [
                detail("Using \(connection?.name ?? "codex")/\(chosen.model) from this account's model catalog.")
            ]
        )
    }

    static func exitCode(for error: any Error) -> Int32 {
        if case ConnectionError.signInRequired = error { return 77 }
        if error is ConfigurationError || error is ProviderSettingsError || error is ConnectionError
            || error is SessionDestinationError || error is ModelAliasError || error is ThinkingError
            || error is ModelScopeRefusal
        {
            return 78
        }
        if error is CodexAccessError || error is CredentialFileError || error is ClaudeAccessError
            || error is AgyAccessError
            || error is AnthropicEnvironmentAuthError || error is NotSignedIn
        {
            return 77
        }
        if case ModelCatalogError.refused(status: 401) = error { return 77 }
        return 69
    }
}
