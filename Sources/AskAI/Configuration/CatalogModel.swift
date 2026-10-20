/// A model reported by a provider's catalog, with the normal limits the server advertises.
public struct CatalogModel: Codable, Sendable, Equatable {
    public let id: String
    public let contextWindow: Int?
    public let maxOutputTokens: Int?
    /// The reasoning effort names the server reports for this model, in its order. Empty means not reported, which is
    /// unknown and not "none": a model that cannot reason is not the same as a catalog that did not say.
    public let reasoningLevels: [String]
    /// The level the server uses when none is asked for, when it reported one of ``reasoningLevels``.
    public let defaultReasoningLevel: String?

    /// A catalog entry; an absent limit is unknown, not an invented default.
    public init(
        id: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil, reasoningLevels: [String] = [],
        defaultReasoningLevel: String? = nil
    ) {
        self.id = id
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningLevels = reasoningLevels
        self.defaultReasoningLevel = defaultReasoningLevel
    }

    /// The levels for a person: the default marked with `*`, or `unknown` when the server did not say.
    public var reasoningDescription: String {
        guard !reasoningLevels.isEmpty else { return "unknown" }
        return reasoningLevels.map { $0 == defaultReasoningLevel ? $0 + "*" : $0 }.joined(separator: " ")
    }

    /// The most levels kept for one model: far more than any provider offers, so a hostile list cannot grow the cache.
    static let levelLimit = 16

    private enum CodingKeys: String, CodingKey {
        case id, contextWindow, maxOutputTokens, reasoningLevels, defaultReasoningLevel
    }

    /// Reads a catalog written before reasoning levels existed: the missing fields are unknown.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        maxOutputTokens = try values.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        reasoningLevels = try values.decodeIfPresent([String].self, forKey: .reasoningLevels) ?? []
        defaultReasoningLevel = try values.decodeIfPresent(String.self, forKey: .defaultReasoningLevel)
    }

    /// Whether an untrusted descriptor is safe to use in a request and as a terminal label.
    var isValid: Bool {
        Self.validID(id) && (contextWindow.map { $0 > 0 } ?? true) && (maxOutputTokens.map { $0 > 0 } ?? true)
            && reasoningLevels.count <= Self.levelLimit && reasoningLevels.allSatisfy(Self.validLevel)
            && Set(reasoningLevels).count == reasoningLevels.count
            && (defaultReasoningLevel.map { reasoningLevels.contains($0) } ?? true)
    }

    /// A reasoning effort name: 2 to 24 lower-case ASCII letters, which is what every provider uses and nothing that can
    /// break a request body or a terminal.
    static func validLevel(_ level: String) -> Bool {
        (2 ... 24).contains(level.utf8.count) && level.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    static func validID(_ id: String) -> Bool {
        guard PlainToken.matches(id, length: 1 ... 128, extra: "._-"), let first = id.utf8.first else { return false }
        return (first >= 48 && first <= 57) || (first >= 65 && first <= 90) || (first >= 97 && first <= 122)
    }
}
