internal import AemiJSON
public import AemiSearch
public import AskAI
public import AskAgentCore
internal import Foundation

/// `search_session` (t209; the owner, 2026-11-12: the current session only): the model searches this session's whole history, what
/// compaction folded away included: typed lines, replies, tool calls and results, summaries. Ranked snippets, each with its entry;
/// typos and parts of identifiers are found. No other session is read.
public struct SessionSearchTool: Tool {
    public let definition = ToolDefinition(
        name: "search_session",
        description: """
            Search this session's whole history, what compaction folded away included (typed lines, replies, tool calls and results, \
            summaries); typos and parts of identifiers match. kind: user, reply, call, tool, summary.
            """
    ) {
        ToolProperty.string("query")
        ToolProperty.string("kind").optional
        ToolProperty.integer("limit", minimum: 1, maximum: 50).optional
    }

    private let currentSession: @Sendable () -> String?

    /// Searches the session `currentSession` names at the time of each call (a fork or a new session moves it).
    public init(currentSession: @escaping @Sendable () -> String?) { self.currentSession = currentSession }

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let root = (try? AemiJSON.parse(input.bytes))?.root
        guard let text = root?["query"].string, !text.isEmpty else { return .error("Give a query.") }
        guard let path = currentSession() else { return ToolOutput("This conversation has no session to search yet.") }
        let fields = root?["kind"].string.map { ["kind": $0] } ?? [:]
        let limit = root?["limit"].int ?? 10
        return ToolOutput(await Self.answer(SearchQuery(text, fields: fields, limit: limit), in: path))
    }

    /// The hits for `query` in the session at `path`, as text; or why it cannot be searched.
    public static func answer(_ query: SearchQuery, in path: String) async -> String {
        let search = SessionSearch.of(session: path)
        let hits = await search.search(query)
        if await search.unreadable { return "This session is encrypted; searching it is not available yet." }
        return text(of: hits, query: query.text)
    }

    /// One block per hit: `session · kind · entry` then its snippet.
    public static func text(of hits: [SearchHit], query: String) -> String {
        guard !hits.isEmpty else { return "Nothing found for \(query)." }
        return
            hits.map { hit in
                let where_ = [
                    hit.fields["project"], hit.fields["session"], hit.fields["kind"],
                    hit.fields["entry"].map { "entry " + $0 }
                ]
                .compactMap(\.self).joined(separator: " · ")
                return where_ + "\n" + hit.snippet
            }
            .joined(separator: "\n\n")
    }
}
