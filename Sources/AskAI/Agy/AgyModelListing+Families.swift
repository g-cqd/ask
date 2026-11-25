internal import AemiJSON

extension AgyModelListing {
    /// A family of the list's `groupedModels`: one model the server offers at several efforts, each its own id, `<family>-<suffix>`
    /// (`claude-opus-5-5-high`). The family itself is no longer an id the server accepts, so it is kept as an entry whose
    /// reasoning levels are the variants listed; a request for it names the variant of the effort chosen (``AgyRequestEncoder``).
    /// - Parameters:
    ///   - root: the list's body.
    ///   - variants: the chat models kept, by id.
    ///   - order: every listed id, in the list's order, which places each family.
    ///   - standard: the server's default agent model, which names the default effort of its own family.
    /// - Returns: each family with at least one usable variant, in the order of its first variant among `order`.
    static func families(_ root: JSON, variants: [String: CatalogModel], order: [String], standard: String?)
        -> [CatalogModel]
    {
        var found: [(position: Int, model: CatalogModel)] = []
        root["groupedModels"]
            .forEachMember { name, entry in
                let family = String(name)
                guard CatalogModel.validID(family), variants[family] == nil else { return }
                let suffixes = (entry["supportedThinkingLevels"].array ?? []).compactMap { $0["thinkingSuffix"].string }
                // A suffix ask can ask for by name, whose variant is listed and offered for chat.
                let levels = suffixes.filter { suffix in
                    ThinkingLevel(rawValue: suffix)?.isEffort == true
                        && variants["\(family)-\(suffix)"]?.unsuitable == nil
                        && variants["\(family)-\(suffix)"] != nil
                }
                guard let fallback = levels.last else { return }
                let named = standard.flatMap { id in levels.first { "\(family)-\($0)" == id } }
                let chosen = named ?? (levels.contains("high") ? "high" : fallback)
                let limits = variants["\(family)-\(chosen)"]
                let position = levels.compactMap { order.firstIndex(of: "\(family)-\($0)") }.min() ?? order.count
                found.append(
                    (
                        position,
                        CatalogModel(
                            id: family,
                            contextWindow: limits?.contextWindow,
                            maxOutputTokens: limits?.maxOutputTokens,
                            reasoningLevels: levels,
                            defaultReasoningLevel: chosen,
                            supportsThinking: true
                        )
                    )
                )
            }
        return found.sorted { ($0.position, $0.model.id) < ($1.position, $1.model.id) }.map(\.model)
    }
}
