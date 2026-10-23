/// A connection's local model names and default: what the user chose, never what the server reported.
public struct ModelAliases: Codable, Sendable, Equatable {
    /// No aliases and no default.
    public static let empty = ModelAliases()
    /// The newest format this build reads and writes. Version 2 adds a thinking level per alias; a file is written as version 1
    /// while no alias has one, so an older build keeps reading it, and as 2 once one does, so an older build refuses the file
    /// instead of reading it, dropping the levels it does not know, and saving that loss on its next change.
    public static let formatVersion = 2
    /// The most aliases one connection keeps.
    public static let limit = 64

    public private(set) var version = ModelAliases.formatVersion
    /// Alias names to their models, in no particular order.
    public private(set) var aliases: [String: ModelAlias] = [:]
    /// The model, or alias, used when none is asked for.
    public private(set) var defaultModel: String?

    /// No aliases and no default.
    public init() {}

    /// The model a request will name.
    /// - Parameters:
    ///   - requested: what the user asked for: an alias, a server id, or nil for the default.
    ///   - catalog: the models this account lists, when known, so an alias cannot hide one.
    /// - Returns: nil when nothing was asked for and there is no default.
    /// - Throws: `ModelAliasError.ambiguous` or `ModelAliasError.chained`.
    public func choice(requested: String?, catalog: [CatalogModel]) throws(ModelAliasError) -> ModelChoice? {
        guard let asked = requested ?? defaultModel else { return nil }
        let key = asked.lowercased()
        guard let alias = aliases[key] else { return ModelChoice(model: asked) }
        guard !catalog.contains(where: { $0.id.lowercased() == key }) else { throw .ambiguous(key) }
        guard aliases[alias.model.lowercased()] == nil else { throw .chained(key) }
        return ModelChoice(
            model: alias.model, alias: key, contextWindow: alias.contextWindow, maxOutputTokens: alias.maxOutputTokens,
            thinking: alias.thinking)
    }

    /// Adds or replaces an alias.
    /// - Parameters:
    ///   - name: the alias; lower-cased.
    ///   - model: the server's model id.
    ///   - contextWindow: a window the user states, or nil.
    ///   - maxOutputTokens: a reply limit the user states, or nil.
    ///   - thinking: a thinking level for this alias, or nil to leave the configured one.
    ///   - known: the model ids this account lists, when known.
    /// - Throws: a `ModelAliasError` and changes nothing.
    public mutating func set(
        _ name: String, to model: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil,
        thinking: ThinkingLevel? = nil, known: [String] = []
    ) throws(ModelAliasError) {
        let key = name.lowercased()
        guard Self.validName(key) else { throw .invalidName }
        guard CatalogModel.validID(model) else { throw .invalidModel }
        guard (contextWindow ?? 1) > 0, (maxOutputTokens ?? 1) > 0 else { throw .invalidLimit }
        guard model.lowercased() != key else { throw .selfReference(key) }
        guard aliases[model.lowercased()] == nil else { throw .chained(key) }
        guard !known.contains(where: { $0.lowercased() == key }) else { throw .shadowsModel(key) }
        guard aliases[key] != nil || aliases.count < Self.limit else { throw .tooMany }
        aliases[key] = ModelAlias(
            model: model, contextWindow: contextWindow, maxOutputTokens: maxOutputTokens, thinking: thinking)
    }

    /// Removes an alias.
    /// - Parameter name: the alias.
    /// - Throws: `ModelAliasError.notFound`, or `ModelAliasError.isDefault` for the default.
    public mutating func remove(_ name: String) throws(ModelAliasError) {
        let key = name.lowercased()
        guard defaultModel?.lowercased() != key else { throw .isDefault(key) }
        guard aliases.removeValue(forKey: key) != nil else { throw .notFound(key) }
    }

    /// Sets, or with nil clears, the default model.
    /// - Parameter model: an alias or a server id.
    /// - Throws: `ModelAliasError.invalidModel`.
    public mutating func setDefault(_ model: String?) throws(ModelAliasError) {
        if let model, !CatalogModel.validID(model) { throw .invalidModel }
        defaultModel = model
    }

    /// An alias name: 1 to 64 lower-case ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit.
    static func validName(_ name: String) -> Bool {
        PlainToken.word(name, length: 1 ... 64, lowercase: true)
    }

    /// Whether a decoded file is within every rule `set` enforces, so a hand-edited file cannot carry what ask would refuse.
    var isValid: Bool {
        (1 ... Self.formatVersion).contains(version) && aliases.count <= Self.limit
            && aliases.allSatisfy { name, alias in
                Self.validName(name) && CatalogModel.validID(alias.model)
                    && (alias.contextWindow ?? 1) > 0 && (alias.maxOutputTokens ?? 1) > 0
            } && (defaultModel.map(CatalogModel.validID) ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case version, aliases
        case defaultModel = "default"
    }

    /// Reads a file; a missing version or table is the current format's empty one.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.formatVersion
        aliases = try values.decodeIfPresent([String: ModelAlias].self, forKey: .aliases) ?? [:]
        defaultModel = try values.decodeIfPresent(String.self, forKey: .defaultModel)
    }

    /// Same aliases and default. The version is not content: it is derived when written (see ``formatVersion``).
    public static func == (lhs: ModelAliases, rhs: ModelAliases) -> Bool {
        lhs.aliases == rhs.aliases && lhs.defaultModel == rhs.defaultModel
    }

    /// Writes the oldest version that can hold what is stored (see ``formatVersion``).
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(aliases.values.contains { $0.thinking != nil } ? 2 : 1, forKey: .version)
        try values.encode(aliases, forKey: .aliases)
        try values.encodeIfPresent(defaultModel, forKey: .defaultModel)
    }
}
