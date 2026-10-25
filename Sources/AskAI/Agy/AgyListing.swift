/// A model list freshly downloaded from Cloud Code, with the default the server named for it.
public struct AgyListing: Sendable, Equatable {
    public let snapshot: CatalogSnapshot
    public let defaultModelID: String?
}
