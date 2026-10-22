internal import Foundation

/// Model catalogs share a cache policy, not authorization: a native owner resolves its current grant before reading;
/// key-based discovery has only a key-presence scope. Neither may persist a possibly credential-bearing address.
enum ModelCatalogCachePolicy {
    static func permits(_ address: URL) -> Bool {
        address.user == nil && address.password == nil && address.query == nil && address.fragment == nil
    }

    /// Reuse a fresh cache unless explicitly refreshing. Damage is reported and costs only that cache; errors from
    /// a credential reader are not swallowed as cache damage. The nonescaping read is not invoked for refresh.
    static func reuse(
        unless refresh: Bool, notices: inout [String], read: () throws -> CatalogSnapshot?
    ) throws -> CatalogSnapshot? {
        guard !refresh else { return nil }
        do { return try read() } catch let error as ModelCatalogError {
            notices.append("Cached catalog not used: \(error)")
            return nil
        }
    }
}
