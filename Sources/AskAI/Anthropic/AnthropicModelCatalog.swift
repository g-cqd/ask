internal import CryptoKit
public import Foundation

/// Native Anthropic metadata with authorization-scoped caching. Authorization callbacks stay with the credential owner:
/// the read-only callback must never refresh, and the request callback may use the owner's normal refresh path.
public struct AnthropicModelCatalog: Sendable {
    public static let endpoint = AnthropicClient.endpoint.deletingLastPathComponent().appending(path: "models")
    private let url: URL
    private let cache: ModelCatalogFile?
    private let cacheDisabled: Bool
    private let transport: any HTTPTransport
    private let connectionID: UUID?
    private let authorize: @Sendable (Double) async throws -> AnthropicClient.Auth
    private let cachedAuthorization: @Sendable (Double) throws -> AnthropicClient.Auth?

    /// The native catalog at `endpoint`.
    /// - Parameters:
    ///   - endpoint: the native `v1/models` URL, already approved by the endpoint policy.
    ///   - cache: the optional file; addresses that may contain credentials must not be persisted.
    ///   - transport: what sends requests.
    ///   - connectionID: the stable registration identity, when this is a named connection.
    ///   - authorize: the credential owner's authorization for a request at the given wall time.
    ///   - cachedAuthorization: current authorization without a network or a write; nil when none is available.
    public init(
        endpoint: URL = AnthropicModelCatalog.endpoint, cache: ModelCatalogFile?, transport: any HTTPTransport,
        connectionID: UUID? = nil,
        authorize: @escaping @Sendable (Double) async throws -> AnthropicClient.Auth,
        cachedAuthorization: @escaping @Sendable (Double) throws -> AnthropicClient.Auth?
    ) {
        url = endpoint
        let sensitive = !ModelCatalogCachePolicy.permits(endpoint)
        self.cacheDisabled = cache != nil && sensitive
        self.cache = sensitive ? nil : cache
        self.transport = transport
        self.connectionID = connectionID
        self.authorize = authorize
        self.cachedAuthorization = cachedAuthorization
    }

    /// A fresh complete snapshot for the current authorization, without refreshing or repairing anything.
    /// - Parameter now: wall time in seconds since 1970.
    /// - Returns: nil when no matching fresh cache or authorization exists.
    /// - Throws: a cache or authorization-reader error.
    public func cached(now: Double) throws -> CatalogSnapshot? {
        guard let (file, scope) = try cachedScope(now: now) else { return nil }
        return try file.load(scope: scope, now: now).map { CatalogSnapshot(models: $0, notices: []) }
    }

    /// The selected descriptor from a fresh complete cache, without decoding other descriptors.
    /// - Parameters:
    ///   - id: the exact model id.
    ///   - now: wall time in seconds since 1970.
    /// - Returns: nil when not cached for the current authorization.
    /// - Throws: a cache or authorization-reader error.
    public func cachedModel(_ id: String, now: Double) throws -> CatalogModel? {
        guard let (file, scope) = try cachedScope(now: now) else { return nil }
        // @dl:accept -- lookup/snapshot shape only: native scope reads current authorization, not key presence; reusable cache policy is already shared
        return try file.model(id, scope: scope, now: now)
    }

    /// A model list, downloading when needed. Partial pages remain usable but never replace the cache.
    /// - Parameters:
    ///   - now: wall time in seconds since 1970.
    ///   - refresh: explicitly bypass even a fresh cache.
    /// - Returns: descriptors and notices the caller must display.
    /// - Throws: a catalog, authorization or transport error; failed downloads leave the old file alone.
    public func models(now: Double, refresh: Bool = false) async throws -> CatalogSnapshot {
        var notices = cacheDisabled ? ["Model list not cached: its address might contain a credential."] : []
        if let current = try ModelCatalogCachePolicy.reuse(
            unless: refresh, notices: &notices, read: { try cached(now: now) })
        {
            return current
        }
        let auth = try await authorize(now)
        let downloaded = try await AnthropicCatalogClient(transport: transport, endpoint: url).models(auth: auth)
        notices += downloaded.notices
        if downloaded.complete, let cache {
            do { try cache.save(downloaded.models, scope: scope(for: auth), now: now) } catch {
                notices.append("Downloaded model catalog could not be cached: \(error)")
            }
        }
        return CatalogSnapshot(models: downloaded.models, notices: notices)
    }

    /// Do not read a credential at all when no cache exists; ordinary uncached startup has no work here.
    private func cachedScope(now: Double) throws -> (ModelCatalogFile, ModelCatalogScope)? {
        guard let cache, FileManager.default.fileExists(atPath: cache.url.path),
            let auth = try cachedAuthorization(now)
        else { return nil }
        return (cache, scope(for: auth))
    }

    /// An authorization fingerprint, not an account id. Refreshing or replacing a grant invalidates its old metadata;
    /// the raw credential never becomes a stored scope field. PKCE already owns the same SHA-256/base64url primitives.
    private func scope(for auth: AnthropicClient.Auth) -> ModelCatalogScope {
        let identity: (kind: String, value: String)
        switch auth {
            case .subscription(let token): identity = ("subscription", token)
            case .bearer(let token): identity = ("bearer", token)
            case .apiKey(let key): identity = ("api-key", key)
        }
        let fingerprint = Base64URL.encode(Array(SHA256.hash(data: Array(identity.value.utf8))))
        return ModelCatalogScope(
            provider: ProviderSettings.anthropic, accountID: identity.kind + ":" + fingerprint,
            endpoint: url, connectionID: connectionID)
    }
}
