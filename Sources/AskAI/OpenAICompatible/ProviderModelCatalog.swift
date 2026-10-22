public import Foundation

/// The models an OpenAI-compatible provider lists at `GET {baseURL}/models`, kept in a cache so a run starts without a request.
///
/// It describes what the service says about its models (the windows a run's compaction needs) and never chooses one: list order
/// is not taken as a default preference, so the user names the model.
public struct ProviderModelCatalog: Sendable {
    /// What a key stands for in the cache's scope. A key names no account, so a catalog is one per provider and endpoint, and
    /// whether a key was sent.
    private static let keyScope = "api-key"
    private static let keylessScope = "no-key"
    /// The most a listing may be: OpenRouter's was 0.8 MB on 2026-10-20.
    private static let bodyLimit = 4 << 20

    private let name: String
    private let url: URL
    private let apiKey: String?
    private let headers: [String: String]
    private let cache: ModelCatalogFile?
    private let cacheDisabled: Bool
    private let transport: any HTTPTransport

    /// A catalog of the provider `name`.
    /// - Parameters:
    ///   - name: the provider's name, which scopes the cache.
    ///   - baseURL: the API root the provider's requests go under; the list is its `models`.
    ///   - apiKey: sent as a bearer token when there is one. A service that lists without a key is asked without.
    ///   - headers: the extra headers the provider's own requests carry.
    ///   - cache: where the list is kept, or nil to keep none. An address with user information, a query or a fragment
    ///     is not cached: any of those can carry a credential, and the cache must not copy it.
    ///   - transport: what sends the request.
    public init(
        name: String, baseURL: URL, apiKey: String?, headers: [String: String], cache: ModelCatalogFile?,
        transport: any HTTPTransport
    ) {
        self.name = name
        self.url = baseURL.appending(path: "models")
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        self.headers = headers
        let sensitiveAddress =
            baseURL.user != nil || baseURL.password != nil || baseURL.query != nil || baseURL.fragment != nil
        self.cacheDisabled = cache != nil && sensitiveAddress
        self.cache = sensitiveAddress ? nil : cache
        self.transport = transport
    }

    /// A fresh cached list, without a network.
    /// - Parameter now: wall time in seconds since 1970.
    /// - Returns: nil when there is no cache, it is a day old, or it describes another endpoint.
    /// - Throws: ``ModelCatalogError/cache(path:)`` for a cache that cannot be read; nothing is rewritten.
    public func cached(now: Double) throws -> CatalogSnapshot? {
        guard let models = try cache?.load(scope: scope, now: now) else { return nil }
        return CatalogSnapshot(models: models, notices: [])
    }

    /// One model's entry in a fresh cached list, without a network or decoding the other model descriptors.
    /// - Parameters:
    ///   - id: the model's id, as the provider lists it.
    ///   - now: wall time in seconds since 1970.
    /// - Returns: nil when there is no fresh cache or it does not list `id`.
    /// - Throws: ``ModelCatalogError/cache(path:)`` for a cache that cannot be read; nothing is rewritten.
    public func cachedModel(_ id: String, now: Double) throws -> CatalogModel? {
        try cache?.model(id, scope: scope, now: now)
    }

    /// The provider's list, downloading when the cache misses or `refresh` is true.
    /// - Parameters:
    ///   - now: wall time in seconds since 1970.
    ///   - refresh: ask the provider even when the cache is fresh.
    /// - Returns: the models and notices the caller must show: a cache that could not be used or saved, and entries left out.
    /// - Throws: a ``ModelCatalogError`` or the transport's error. A failed download leaves the cache as it was.
    public func models(now: Double, refresh: Bool = false) async throws -> CatalogSnapshot {
        var notices =
            cacheDisabled
            ? [
                "Model list not cached: its address has user information, a query or a fragment that might contain a credential."
            ]
            : []
        if !refresh {
            do { if let current = try cached(now: now) { return current } } catch let error as ModelCatalogError {
                notices.append("Cached catalog not used: \(error)")
            }
        }
        var request = HTTPRequest.account("GET", url)
        if let apiKey { request.headers.append(("authorization", "Bearer \(apiKey)")) }
        request.headers += headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        let reply = try await transport.collecting(request, limit: Self.bodyLimit)
        guard reply.status == 200 else { throw ModelCatalogError.refused(status: reply.status) }
        let listing = try ModelListing(decoding: reply.body)
        if listing.skipped > 0 {
            notices.append(
                "\(listing.skipped) listed entries were left out: no usable id, a repeat, or the catalog limit.")
        }
        do { try cache?.save(listing.models, scope: scope, now: now) } catch {
            notices.append("Downloaded model catalog could not be cached: \(error)")
        }
        return CatalogSnapshot(models: listing.models, notices: notices)
    }

    private var scope: ModelCatalogScope {
        ModelCatalogScope(
            provider: name, accountID: apiKey == nil ? Self.keylessScope : Self.keyScope, endpoint: url)
    }
}
