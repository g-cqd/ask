public import Foundation

/// The Antigravity account's model list, kept in a cache bound to the project it was requested for.
///
/// A run reads the cache and never the network: the list is fetched by `ask models agy`, and a run that has none knows no window until
/// the provider's refusal says one. Reading never refreshes a token or repairs a file.
public struct AgyModelCatalog: Sendable {
    /// The endpoint the list comes from, which is also part of the cache's scope.
    public static let endpoint = URL(
        string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    private let credentials: CredentialFile
    private let cache: ModelCatalogFile
    private let cloud: AgyCloudClient
    private let access: AgyAccess

    /// Discovery through `access`, with the cache in `cache` and the stored sign-in in `credentials`.
    public init(credentials: CredentialFile, cache: ModelCatalogFile, cloud: AgyCloudClient, access: AgyAccess) {
        self.credentials = credentials
        self.cache = cache
        self.cloud = cloud
        self.access = access
    }

    /// A fresh cached list for the stored sign-in's project, without a network, a refresh or a write.
    /// - Parameter now: wall time in seconds since 1970.
    /// - Returns: nil when signed out, not yet onboarded, or without a matching fresh cache.
    /// - Throws: a credential-file or cache error.
    public func cached(now: Double) throws -> CatalogSnapshot? {
        guard let scope = try storedScope() else { return nil }
        return try cache.load(scope: scope, now: now).map { CatalogSnapshot(models: $0) }
    }

    /// One model of a fresh cached list, decoding no other.
    /// - Parameters:
    ///   - id: the model's id, exactly as the server lists it.
    ///   - now: wall time in seconds since 1970.
    /// - Returns: nil when there is no matching fresh cache or it does not list `id`.
    /// - Throws: a credential-file or cache error.
    public func cachedModel(_ id: String, now: Double) throws -> CatalogModel? {
        guard let scope = try storedScope() else { return nil }
        return try cache.model(id, scope: scope, now: now)
    }

    /// Downloads the list and keeps it.
    /// - Parameter now: wall time in seconds since 1970.
    /// - Returns: the models and the server's default, with a notice when the cache could not be written.
    /// - Throws: an ``AgyAccessError``, a ``ModelCatalogError`` or the transport's error; a failed download leaves the cache as it was.
    public func refreshed(now: Double) async throws -> AgyListing {
        let session = try await access.session(now: now)
        let list = try await cloud.models(accessToken: session.accessToken, project: session.projectID)
        var notices: [String] = []
        do { try cache.save(list.models, scope: scope(project: session.projectID), now: now) } catch {
            notices.append("Downloaded model catalog could not be cached: \(error)")
        }
        return AgyListing(
            snapshot: CatalogSnapshot(models: list.models, notices: notices), defaultModelID: list.defaultModelID)
    }

    private func storedScope() throws -> ModelCatalogScope? {
        guard let project = try credentials.loadAgy()?.projectID else { return nil }
        return scope(project: project)
    }

    private func scope(project: String) -> ModelCatalogScope {
        ModelCatalogScope(provider: ProviderSettings.agy, accountID: project, endpoint: Self.endpoint)
    }
}
