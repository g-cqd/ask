internal import AemiSearch
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// `/search QUERY` (t209): the same search as the model's `search_sessions`, shown to the person.
enum SessionSearchCommand {
    static func answer(to arguments: String) async -> String {
        let query = arguments.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return "Give words to search for: /search cache key." }
        let hits = await SessionSearch.shared.search(SearchQuery(query, limit: 10))
        return SessionSearchTool.text(of: hits, query: query)
    }
}
