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
        model = CatalogModel(
            id: id, contextWindow: context.flatMap { $0 > 0 ? $0 : nil },
            maxOutputTokens: output.flatMap { $0 > 0 ? $0 : nil })
    }
}
