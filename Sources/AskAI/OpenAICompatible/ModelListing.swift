internal import AemiJSON

/// The models an OpenAI-style `GET /models` answer lists, with the limits it states and none it does not.
///
/// Services agree on `{"data":[{"id":…}]}` and nothing else (diary 57): OpenRouter states `context_length` and
/// `top_provider`, Hugging Face's router a `context_length` for each service that can serve a model, NVIDIA no limit at all.
/// A limit the answer does not state is unknown, never a default, and a model keeps the smallest window the answer gives it: the
/// conservative figure among the known routes, not a guarantee about a route whose window is unknown.
struct ModelListing: Sendable, Equatable {
    let models: [CatalogModel]
    /// How many entries were left out: not an object, no usable id, or the same id again.
    let skipped: Int

    /// The most entries kept, so a hostile answer cannot grow the cache.
    static let entryLimit = 5000
    /// The largest window believed: far past any model, so a nonsense figure is not trusted.
    static let largestWindow = 100_000_000

    /// Reads the listing in `body`.
    /// - Throws: ``ModelCatalogError/invalidResponse`` when it is not `{"data":[…]}` and ``ModelCatalogError/noModels`` when no
    ///   entry has a usable id.
    init(decoding body: [UInt8]) throws(ModelCatalogError) {
        let entries: [Lenient<ListedModel>]
        do { entries = try AemiJSON.JSONDecoder().decode(Wrapper.self, from: body).data } catch {
            throw .invalidResponse
        }
        var seen = Set<String>()
        var kept: [CatalogModel] = []
        for entry in entries {
            guard let listed = entry.value, let id = listed.id, CatalogModel.validID(id), kept.count < Self.entryLimit,
                seen.insert(id).inserted
            else { continue }
            let window = Self.window(of: listed)
            let output = listed.topProvider?.value?.maxCompletionTokens?.value.flatMap { $0 > 0 ? $0 : nil }
            kept.append(
                CatalogModel(
                    id: id, contextWindow: window, maxOutputTokens: output.flatMap { $0 < (window ?? .max) ? $0 : nil })
            )
        }
        guard !kept.isEmpty else { throw .noModels }
        models = kept
        skipped = entries.count - kept.count
    }

    /// The smallest believable window the entry states anywhere, or nil when it states none.
    private static func window(of listed: ListedModel) -> Int? {
        let live = (listed.providers?.value ?? []).compactMap(\.value).filter { $0.status == "live" }
        let figures =
            [listed.contextWindow, listed.contextLength, listed.topProvider?.value?.contextLength]
            + live.map(\.contextLength)
        return figures.compactMap { $0?.value }.filter { (1 ... largestWindow).contains($0) }.min()
    }

    private struct Wrapper: Decodable {
        let data: [Lenient<ListedModel>]
    }
}
