internal import AemiJSON

/// Reads the model list Cloud Code returns, which describes more than chat models.
///
/// The server marks no entry "chat". Its list has internal completion models, tab-completion models with a 4,096-token output, an image
/// model and an audio one, beside the agent models. The rule is ask's product choice, probed against the live list (ADR-0087): every
/// entry it keeps answered a trivial prompt, and the tab and image entries it drops also answer, so it is conservative, not a fact.
enum AgyModelListing {
    /// The chat models of a list body.
    /// - Parameter body: the response body.
    /// - Returns: the models and the server's default when it is among them.
    /// - Throws: ``ModelCatalogError`` when the body is not a model list or lists no usable model.
    static func parse(_ body: [UInt8]) throws -> AgyModelList {
        guard let root = try? AemiJSON.parse(body).root, root.isObject, root["models"].isObject else {
            throw ModelCatalogError.invalidResponse
        }
        let models = root["models"]
        let named = namedIDs(root)
        var reasons: [String: String] = [:]
        for (key, reason) in [
            ("tabModelIds", "tab completion"), ("imageGenerationModelIds", "image generation"),
            ("audioTranscriptionModelIds", "audio transcription")
        ] {
            for id in strings(root[key]) { reasons[id] = reasons[id] ?? reason }
        }
        var capable: [String] = []
        models.forEachMember { name, entry in
            if entry["supportsThinking"].bool == true { capable.append(String(name)) }
        }
        var seen = Set<String>()
        var rest: [String] = []
        models.forEachMember { name, _ in rest.append(String(name)) }
        let all = (named + capable.sorted() + rest.sorted())
            .compactMap { id -> CatalogModel? in
                let entry = models[id]
                guard entry.isObject, CatalogModel.validID(id), seen.insert(id).inserted else { return nil }
                let chat = entry["isInternal"].bool != true && reasons[id] == nil
                let unsuitable = reasons[id] ?? (entry["isInternal"].bool == true ? "internal" : nil)
                // Not named for agent use and not a thinking model: the server does not offer it for chat.
                let offered = named.contains(id) || capable.contains(id)
                return CatalogModel(
                    id: id, contextWindow: positive(entry["maxTokens"]),
                    maxOutputTokens: positive(entry["maxOutputTokens"]),
                    supportsThinking: entry["supportsThinking"].bool,
                    unsuitable: chat && !offered ? "not offered for chat" : unsuitable)
            }
        // The default and the emptiness test are about the useful models, as before this list also held the rest.
        let kept = all.filter { $0.unsuitable == nil }
        guard !kept.isEmpty else { throw ModelCatalogError.noModels }
        let standard = root["defaultAgentModelId"].string
        return AgyModelList(
            models: all, defaultModelID: standard.flatMap { id in kept.contains { $0.id == id } ? id : nil })
    }

    /// The ids the server names for agent use: its groups in order, then command models, then tiered models by tier name.
    private static func namedIDs(_ root: JSON) -> [String] {
        var ids = (root["agentModelSorts"].array ?? [])
            .flatMap { sort in
                (sort["groups"].array ?? []).flatMap { strings($0["modelIds"]) }
            }
        ids += strings(root["commandModelIds"])
        var tiers: [(String, [String])] = []
        root["tieredModelIds"].forEachMember { tier, list in tiers.append((String(tier), strings(list))) }
        return ids + tiers.sorted { $0.0 < $1.0 }.flatMap(\.1)
    }

    private static func strings(_ node: JSON) -> [String] { (node.array ?? []).compactMap(\.string) }

    private static func positive(_ node: JSON) -> Int? { node.int.flatMap { $0 > 0 ? $0 : nil } }
}
