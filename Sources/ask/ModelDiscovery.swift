internal import AskAI
internal import AskAgentCore
internal import Foundation

/// The CLI's binding of discovery to the current connection; provider behavior stays in AskAI.
enum ModelDiscovery {
    static func codex(environment: [String: String], connection: ConnectionRecord? = nil) -> CodexModelCatalog {
        let credentials = NamedConnections.file(for: connection, environment: environment)
        return CodexModelCatalog(
            credentials: credentials,
            cache: ModelCatalogFile(
                url: credentials.url.deletingLastPathComponent().appending(path: "models-codex.json")),
            transport: URLSessionTransport(), connection: connection)
    }

    /// Resolve normally first; only a missing Codex default requires discovery. Explicit model ids never need a network.
    static func resolve(
        providers: ProviderSettings, provider: String?, model: String?, environment: [String: String],
        allowNetwork: Bool
    ) async throws -> (model: ResolvedModel, notices: [String]) {
        let selected = providers.selectedProvider(provider)
        let connection: ConnectionRecord?
        var notices: [String] = []
        if [ProviderSettings.anthropic, ProviderSettings.codex].contains(selected) {
            connection = nil
        } else {
            let listing = try NamedConnections.registry(environment: environment).list()
            notices = listing.notices
            connection = listing.records.first { $0.name == selected.lowercased() }
        }
        var aliases = ModelAliases.empty
        if let connection {
            do { aliases = try NamedConnections.aliases(for: connection, environment: environment).load() } catch {
                // A damaged file refuses a run that relies on it (the default model would silently change), but not one that
                // names a server model outright.
                guard model != nil else { throw error }
                notices.append("Aliases not used: \(error)")
            }
        }
        let resolve: ([CatalogModel]) throws -> ResolvedModel = { catalog in
            try providers.resolve(
                provider: provider, model: model, environment: environment, catalog: catalog, connection: connection,
                aliases: aliases,
                storedKeys: { () throws(CredentialFileError) in
                    try CredentialFile.standard(environment: environment).loadKeys().mapValues(\.key)
                })
        }
        let initial: ResolvedModel
        do { initial = try resolve([]) } catch ProviderSettingsError.noModel(let name)
            where name == ProviderSettings.codex
        {
            let catalog = codex(environment: environment, connection: connection)
            let snapshot: CatalogSnapshot
            if allowNetwork {
                snapshot = try await catalog.models(now: Date().timeIntervalSince1970)
            } else {
                guard let cached = try catalog.cached(now: Date().timeIntervalSince1970) else {
                    throw ProviderSettingsError.noModel(provider: name)
                }
                snapshot = cached
            }
            let chosen = try resolve(snapshot.models)
            return (
                chosen,
                notices + snapshot.notices + [
                    "Using \(connection?.name ?? "codex")/\(chosen.model) from this account's model catalog."
                ]
            )
        }
        guard initial.provider == .codex else {
            return try withListedLimits(initial, environment: environment, resolve: resolve, notices: notices)
        }
        do {
            guard
                let cached = try codex(environment: environment, connection: connection)
                    .cached(now: Date().timeIntervalSince1970)
            else {
                return (initial, notices + announcement(initial))
            }
            let chosen = try resolve(cached.models)
            return (chosen, notices + cached.notices + announcement(chosen))
        } catch { return (initial, notices + ["Model catalog not used for the explicit model: \(error)"]) }
    }

    /// The run's model with the limits its provider's cached list states, when there is a fresh one. Never a network: the list is
    /// fetched by `ask models NAME`, and a run that has none simply knows no window until the provider's refusal says one. Only
    /// the run's own model is read from the list: it can hold hundreds, and reading them all cost 2 ms of the start (diary 55).
    private static func withListedLimits(
        _ initial: ResolvedModel, environment: [String: String], resolve: ([CatalogModel]) throws -> ResolvedModel,
        notices: [String]
    ) throws -> (model: ResolvedModel, notices: [String]) {
        let listed: CatalogModel?
        do {
            listed = try ProviderModelDiscovery.catalog(for: initial, environment: environment)?
                .cachedModel(initial.model, now: Date().timeIntervalSince1970)
        } catch { return (initial, notices + ["Model list not used: \(error)"] + announcement(initial)) }
        guard let listed else { return (initial, notices + announcement(initial)) }
        let chosen = try resolve([listed])
        return (chosen, notices + announcement(chosen))
    }

    /// Says which server model an alias stood for, so a run never hides what it sent.
    private static func announcement(_ resolved: ResolvedModel) -> [String] {
        guard let alias = resolved.alias, let connection = resolved.connection else { return [] }
        return ["Using \(connection.name)/\(alias), which is \(resolved.model)."]
    }

    static func exitCode(for error: any Error) -> Int32 {
        if case ConnectionError.signInRequired = error { return 77 }
        if error is ConfigurationError || error is ProviderSettingsError || error is ConnectionError
            || error is SessionDestinationError || error is ModelAliasError
        {
            return 78
        }
        if error is CodexAccessError || error is CredentialFileError { return 77 }
        if case ModelCatalogError.refused(status: 401) = error { return 77 }
        return 69
    }
}
