/// The small, untrusted part of a Codex model descriptor ask uses. Instructions and experimental fields are ignored.
struct CodexCatalogEntry: Decodable {
    let model: CatalogModel?
    let priority: Int

    private enum CodingKeys: String, CodingKey {
        case slug, visibility, priority
        case supportedInAPI = "supported_in_api"
        case inputModalities = "input_modalities"
        case contextWindow = "context_window"
        case maxOutputTokens = "max_output_tokens"
        case reasoningLevels = "supported_reasoning_levels"
        case defaultLevel = "default_reasoning_level"
    }

    /// One reported level, tolerating both shapes seen or assumed: `{"effort": "low", ...}` and `"low"`. Anything else is
    /// nothing, so one odd element cannot cost the rest of the list.
    private struct Level: Decodable {
        let name: String?

        init(from decoder: any Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
                name = text
                return
            }
            let keyed = try? decoder.container(keyedBy: Key.self)
            name = try? keyed?.decode(String.self, forKey: .effort)
        }

        private enum Key: String, CodingKey { case effort }
    }

    init(from decoder: any Decoder) throws {
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        priority = (try? fields?.decode(Int.self, forKey: .priority)) ?? Int.max
        guard let id = try? fields?.decode(String.self, forKey: .slug),
            CatalogModel.validID(id),
            (try? fields?.decode(String.self, forKey: .visibility)) != "hide",
            (try? fields?.decode(Bool.self, forKey: .supportedInAPI)) != false
        else {
            model = nil
            return
        }
        if let modalities = try? fields?.decode([String].self, forKey: .inputModalities), !modalities.contains("text") {
            model = nil
            return
        }
        let context = try? fields?.decode(Int.self, forKey: .contextWindow)
        let output = try? fields?.decode(Int.self, forKey: .maxOutputTokens)
        var levels: [String] = []
        for level in (try? fields?.decode([Level].self, forKey: .reasoningLevels)) ?? [] {
            guard let name = level.name, CatalogModel.validLevel(name), !levels.contains(name),
                levels.count < CatalogModel.levelLimit
            else { continue }
            levels.append(name)
        }
        let standard = try? fields?.decode(String.self, forKey: .defaultLevel)
        model = CatalogModel(
            id: id, contextWindow: context.flatMap { $0 > 0 ? $0 : nil },
            maxOutputTokens: output.flatMap { $0 > 0 ? $0 : nil }, reasoningLevels: levels,
            defaultReasoningLevel: standard.flatMap { levels.contains($0) ? $0 : nil },
            acceptsImages: (try? fields?.decode([String].self, forKey: .inputModalities))?.contains("image"))
    }
}
