/// A model reported by a provider's catalog, with the normal limits the server advertises.
public struct CatalogModel: Codable, Sendable, Equatable {
    public let id: String
    public let contextWindow: Int?
    public let maxOutputTokens: Int?

    /// A catalog entry; an absent limit is unknown, not an invented default.
    public init(id: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil) {
        self.id = id
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }

    /// Whether an untrusted descriptor is safe to use in a request and as a terminal label.
    var isValid: Bool {
        Self.validID(id) && (contextWindow.map { $0 > 0 } ?? true) && (maxOutputTokens.map { $0 > 0 } ?? true)
    }

    static func validID(_ id: String) -> Bool {
        guard PlainToken.matches(id, length: 1 ... 128, extra: "._-"), let first = id.utf8.first else { return false }
        return (first >= 48 && first <= 57) || (first >= 65 && first <= 90) || (first >= 97 && first <= 122)
    }
}
