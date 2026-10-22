internal import Foundation

/// Reads native model metadata with the same authorization as Messages, retaining intact descriptors if pagination
/// becomes unusable. A partial download is usable for inspection but must not replace a complete cache.
struct AnthropicCatalogClient: Sendable {
    struct Download: Sendable {
        let models: [CatalogModel]
        let notices: [String]
        let complete: Bool
    }

    static let endpoint = AnthropicClient.endpoint.deletingLastPathComponent().appending(path: "models")
    static let maximumPages = 8
    static let maximumModels = 5000
    private let transport: any HTTPTransport
    private let endpoint: URL

    init(transport: any HTTPTransport, endpoint: URL = AnthropicCatalogClient.endpoint) {
        self.transport = transport
        self.endpoint = endpoint
    }

    /// Downloads bounded pages. Refusals report status only, never the response body.
    /// - Throws: ``ModelCatalogError`` or the transport's error; no file is written.
    func models(auth: AnthropicClient.Auth) async throws -> Download {
        var collected = Collected()
        var cursor: String?
        var cursors = Set<String>()
        for _ in 0 ..< Self.maximumPages {
            let request = HTTPRequest(
                url: try pageURL(after: cursor), method: "GET", headers: AnthropicClient.headers(for: auth), body: [])
            let reply = try await transport.collecting(request, limit: 2 << 20)
            guard reply.status == 200 else { throw ModelCatalogError.refused(status: reply.status) }
            let page = try AnthropicModelListing(decoding: reply.body)
            collected.append(page)
            if collected.limited {
                return try collected.finish(
                    complete: false, reason: "The model-list limit was reached; later entries are not shown or cached.")
            }
            guard page.hasMore == true else {
                return try collected.finish(
                    complete: page.hasMore == false,
                    reason: page.hasMore == nil
                        ? "Pagination metadata is unusable; this partial list is not cached." : nil)
            }
            guard let next = page.lastID, cursors.insert(next).inserted else {
                return try collected.finish(
                    complete: false, reason: "The model-list cursor did not advance; this partial list is not cached.")
            }
            cursor = next
        }
        return try collected.finish(
            complete: false, reason: "The model-list page limit was reached; this partial list is not cached.")
    }

    private func pageURL(after cursor: String?) throws(ModelCatalogError) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw .invalidResponse
        }
        components.queryItems =
            (components.queryItems ?? []).filter { !["limit", "after_id"].contains($0.name) }
            + [URLQueryItem(name: "limit", value: "1000")]
            + (cursor.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
        guard let url = components.url else { throw .invalidResponse }
        return url
    }

    private struct Collected {
        var models: [CatalogModel] = []
        var seen = Set<String>()
        var skipped = 0
        var limited = false

        mutating func append(_ page: AnthropicModelListing) {
            skipped += page.skipped
            for model in page.models {
                guard seen.insert(model.id).inserted else {
                    skipped += 1
                    continue
                }
                guard models.count < AnthropicCatalogClient.maximumModels else {
                    limited = true
                    return
                }
                models.append(model)
            }
        }

        func finish(complete: Bool, reason: String? = nil) throws(ModelCatalogError) -> Download {
            guard !models.isEmpty else { throw .noModels }
            var notices = skipped > 0 ? ["\(skipped) model entries were left out: invalid or repeated ids."] : []
            if let reason { notices.append(reason) }
            return Download(models: models, notices: notices, complete: complete)
        }
    }
}
