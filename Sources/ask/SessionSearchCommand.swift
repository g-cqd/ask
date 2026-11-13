internal import AemiSearch
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// `/search QUERY` (t209): the same search of the current session as the model's `search_session`, shown to the person.
enum SessionSearchCommand {
    static func answer(to arguments: String, session: SessionRecorder?) async -> String {
        let query = arguments.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return "Give words to search for: /search cache key." }
        guard let session else { return "This conversation has no session to search yet." }
        return await SessionSearchTool.answer(SearchQuery(query, limit: 10), in: session)
    }
}
