/// The chat models an Antigravity account lists, and the one the server names as its default when that model is listed.
public struct AgyModelList: Sendable, Equatable {
    public let models: [CatalogModel]
    public let defaultModelID: String?
}
