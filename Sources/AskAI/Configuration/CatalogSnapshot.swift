/// Usable catalog data and any cache problem that must be reported without discarding a successful download.
public struct CatalogSnapshot: Sendable, Equatable {
    public let models: [CatalogModel]
    public let notices: [String]

    /// A snapshot of `models`, with the problems found on the way to them.
    public init(models: [CatalogModel], notices: [String] = []) {
        self.models = models
        self.notices = notices
    }
}
