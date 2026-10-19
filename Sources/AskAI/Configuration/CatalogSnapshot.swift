/// Usable catalog data and any cache problem that must be reported without discarding a successful download.
public struct CatalogSnapshot: Sendable, Equatable {
    public let models: [CatalogModel]
    public let notices: [String]
}
