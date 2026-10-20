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
        let resolve: ([CatalogModel]) throws -> ResolvedModel = { catalog in
            try providers.resolve(
                provider: provider, model: model, environment: environment, catalog: catalog, connection: connection,
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
        guard initial.provider == .codex else { return (initial, notices) }
        do {
            guard
                let cached = try codex(environment: environment, connection: connection)
                    .cached(now: Date().timeIntervalSince1970)
            else {
                return (initial, notices)
            }
            return (try resolve(cached.models), notices + cached.notices)
        } catch { return (initial, notices + ["Model catalog not used for the explicit model: \(error)"]) }
    }

    static func exitCode(for error: any Error) -> Int32 {
        if case ConnectionError.signInRequired = error { return 77 }
        if error is ConfigurationError || error is ProviderSettingsError || error is ConnectionError
            || error is SessionDestinationError
        {
            return 78
        }
        if error is CodexAccessError || error is CredentialFileError { return 77 }
        if case ModelCatalogError.refused(status: 401) = error { return 77 }
        return 69
    }
}
