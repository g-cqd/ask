/// A model reported by a provider's catalog, with the normal limits the server advertises.
public struct CatalogModel: Codable, Sendable, Equatable {
    public let id: String
    /// Advertised native wire protocol when one account serves multiple APIs.
    public let api: String?
    public let contextWindow: Int?
    public let maxOutputTokens: Int?
    /// The reasoning effort names the server reports for this model, in its order. Empty means not reported, which is
    /// unknown and not "none": a model that cannot reason is not the same as a catalog that did not say.
    public let reasoningLevels: [String]
    /// The level the server uses when none is asked for, when it reported one of ``reasoningLevels``.
    public let defaultReasoningLevel: String?
    /// Whether the provider explicitly reports thinking support; nil is unknown, not false.
    public let supportsThinking: Bool?
    /// The modes the provider explicitly reports as supported. Empty is unknown unless ``supportsThinking`` is false.
    public let thinkingModes: [ThinkingMode]
    /// Whether the provider reports that the model takes images; nil is unknown, not false.
    public let acceptsImages: Bool?

    /// A catalog entry; an absent limit is unknown, not an invented default.
    public init(
        id: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil, reasoningLevels: [String] = [],
        // @dl:accept -- optional descriptor fields resemble credential initializer fields only by shape
        defaultReasoningLevel: String? = nil, supportsThinking: Bool? = nil, thinkingModes: [ThinkingMode] = [],
        // @dl:accept -- initializer parameters repeat the stored fields by design
        api: String? = nil, acceptsImages: Bool? = nil
    ) {
        self.acceptsImages = acceptsImages
        self.id = id
        self.api = api
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningLevels = reasoningLevels
        self.defaultReasoningLevel = defaultReasoningLevel
        self.supportsThinking = supportsThinking
        self.thinkingModes = thinkingModes
    }

    /// The levels for a person: the default marked with `*`, or `unknown` when the server did not say.
    public var reasoningDescription: String {
        guard !reasoningLevels.isEmpty else { return "unknown" }
        return reasoningLevels.map { $0 == defaultReasoningLevel ? $0 + "*" : $0 }.joined(separator: " ")
    }

    /// The most levels kept for one model: far more than any provider offers, so a hostile list cannot grow the cache.
    static let levelLimit = 16

    private enum CodingKeys: String, CodingKey {
        case id, api, contextWindow, maxOutputTokens, reasoningLevels, defaultReasoningLevel, supportsThinking,
            thinkingModes, acceptsImages
    }

    /// Reads a catalog written before reasoning levels existed: the missing fields are unknown.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        api = try values.decodeIfPresent(String.self, forKey: .api)
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        maxOutputTokens = try values.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        reasoningLevels = try values.decodeIfPresent([String].self, forKey: .reasoningLevels) ?? []
        defaultReasoningLevel = try values.decodeIfPresent(String.self, forKey: .defaultReasoningLevel)
        supportsThinking = try values.decodeIfPresent(Bool.self, forKey: .supportsThinking)
        thinkingModes = try values.decodeIfPresent([ThinkingMode].self, forKey: .thinkingModes) ?? []
        acceptsImages = try values.decodeIfPresent(Bool.self, forKey: .acceptsImages)
    }

    /// Whether an untrusted descriptor is safe to use in a request and as a terminal label.
    var isValid: Bool {
        Self.validID(id) && (contextWindow.map { $0 > 0 } ?? true) && (maxOutputTokens.map { $0 > 0 } ?? true)
            && reasoningLevels.count <= Self.levelLimit && reasoningLevels.allSatisfy(Self.validLevel)
            && Set(reasoningLevels).count == reasoningLevels.count
            && (defaultReasoningLevel.map { reasoningLevels.contains($0) } ?? true)
            && Set(thinkingModes).count == thinkingModes.count
    }

    /// A reasoning effort name: 2 to 24 lower-case ASCII letters, which is what every provider uses and nothing that can
    /// break a request body or a terminal.
    static func validLevel(_ level: String) -> Bool {
        (2 ... 24).contains(level.utf8.count) && level.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    /// A model id: a plain word that may also contain `/` and `:`, and one leading `~`, which the real lists use (`org/model`,
    /// `model:free`, OpenRouter's `~vendor/model-latest`). It goes into a JSON body and onto a terminal and never into a path.
    static func validID(_ id: String) -> Bool {
        guard id.utf8.count <= 128 else { return false }
        return PlainToken.word(
            id.hasPrefix("~") ? String(id.dropFirst()) : id, length: 1 ... 128, lowercase: false, marks: "/:")
    }
}
