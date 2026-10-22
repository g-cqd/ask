internal import AemiJSON

/// One native Anthropic model-list page. Kept separate from OpenAI-style discovery: its limits and thinking flags
/// have different wire names and meanings (diary 2026-10-22-07).
struct AnthropicModelListing {
    let models: [CatalogModel]
    let skipped: Int
    let hasMore: Bool?
    let lastID: String?

    /// Reads a page. A missing or damaged pagination flag is unknown, never a false promise of completeness.
    /// - Throws: ``ModelCatalogError/invalidResponse`` when the page cannot be read.
    init(decoding bytes: [UInt8]) throws(ModelCatalogError) {
        let page: Page
        do { page = try AemiJSON.JSONDecoder().decode(Page.self, from: bytes) } catch { throw .invalidResponse }
        var seen = Set<String>()
        let kept = page.data.compactMap { entry -> CatalogModel? in
            guard let model = entry.value?.model, seen.insert(model.id).inserted else { return nil }
            return model
        }
        models = kept
        skipped = page.data.count - kept.count
        hasMore = page.hasMore?.value
        lastID = page.lastID?.value.flatMap { CatalogModel.validID($0) ? $0 : nil }
    }

    private struct Page: Decodable {
        let data: [Lenient<AnthropicCatalogEntry>]
        let hasMore: Lenient<Bool>?
        let lastID: Lenient<String>?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case lastID = "last_id"
        }
    }
}
