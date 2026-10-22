/// Codex discovery through ask's credential owner, with a cache bound to the current account and versioned endpoint.
public struct CodexModelCatalog: Sendable {
    private let credentials: CredentialFile
    private let cache: ModelCatalogFile
    private let transport: any HTTPTransport
    private let connection: ConnectionRecord?

    /// Discovery using only ask's own credentials and a replaceable catalog file.
    public init(
        credentials: CredentialFile, cache: ModelCatalogFile, transport: any HTTPTransport,
        connection: ConnectionRecord? = nil
    ) {
        self.credentials = credentials
        self.cache = cache
        self.transport = transport
        self.connection = connection
    }

    /// A fresh local snapshot for the current account, without refreshing tokens or using a network.
    /// - Parameter now: wall time in seconds since 1970.
    /// - Returns: nil when signed out or without a matching fresh cache.
    /// - Throws: a credential-file or cache error; nothing is rewritten.
    public func cached(now: Double) throws -> CatalogSnapshot? {
        guard let current = try credentials.loadCodex(connection: connection),
            let models = try cache.load(scope: scope(for: current), now: now)
        else { return nil }
        // @dl:accept -- the cache return shape is shared, but Codex must load its account identity before naming its scope; key-based discovery has no credential-owner read
        return CatalogSnapshot(models: models, notices: [])
    }

    /// The account's listed models, downloading when the cache misses or `refresh` is true.
    /// - Parameters:
    ///   - now: wall time in seconds since 1970.
    ///   - refresh: explicitly bypass even a fresh cache.
    /// - Returns: usable models and notices about any cache failure; callers must display the notices.
    /// - Throws: credential or network errors, or ``ModelCatalogError``. A failed download preserves the cache.
    public func models(now: Double, refresh: Bool = false) async throws -> CatalogSnapshot {
        var notices: [String] = []
        if !refresh {
            do { if let current = try cached(now: now) { return current } } catch let error as ModelCatalogError {
                notices.append("Cached catalog not used: \(error)")
            }
        }
        let current: CodexCredentials
        do {
            current = try await CodexAccess(
                file: credentials, client: CodexAuthClient(transport: transport), connection: connection
            )
            .credentials(now: now)
        } catch CodexAccessError.signedOut {
            if let connection { throw ConnectionError.signInRequired(name: connection.name, provider: .codex) }
            throw CodexAccessError.signedOut
        }
        let models = try await CodexCatalogClient(transport: transport).models(credentials: current)
        do { try cache.save(models, scope: scope(for: current), now: now) } catch {
            notices.append("Downloaded model catalog could not be cached: \(error)")
        }
        return CatalogSnapshot(models: models, notices: notices)
    }

    private func scope(for credentials: CodexCredentials) -> ModelCatalogScope {
        ModelCatalogScope(
            provider: ProviderSettings.codex, accountID: credentials.accountID, endpoint: CodexCatalogClient.endpoint,
            connectionID: connection?.id)
    }
}
