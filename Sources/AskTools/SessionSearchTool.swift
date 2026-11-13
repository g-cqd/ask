internal import AemiJSON
public import AemiSearch
public import AskAI
public import AskAgentCore
internal import Foundation

/// `search_sessions` (t209): the model searches every plain session on this machine, past ones included, for what the current
/// context no longer holds: typed lines, replies, tool calls and results, compaction summaries. Ranked snippets, each with its session
/// and entry; typos and parts of identifiers are found.
public struct SessionSearchTool: Tool {
    public let definition = ToolDefinition(
        name: "search_sessions",
        description: """
            Search every past and current session on this machine (typed lines, replies, tool calls and results, summaries); typos and \
            parts of identifiers match. kind: user, reply, call, tool, summary. project: the session folder's name.
            """
    ) {
        ToolProperty.string("query")
        ToolProperty.string("kind").optional
        ToolProperty.string("project").optional
        ToolProperty.integer("limit", minimum: 1, maximum: 50).optional
    }

    private let search: SessionSearch

    public init(search: SessionSearch = .shared) { self.search = search }

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let root = (try? AemiJSON.parse(input.bytes))?.root
        guard let text = root?["query"].string, !text.isEmpty else { return .error("Give a query.") }
        var fields: [String: String] = [:]
        if let kind = root?["kind"].string { fields["kind"] = kind }
        if let project = root?["project"].string { fields["project"] = project }
        let limit = root?["limit"].int ?? 10
        let hits = await search.search(SearchQuery(text, fields: fields, limit: limit))
        return ToolOutput(Self.text(of: hits, query: text))
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
