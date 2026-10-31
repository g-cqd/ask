internal import AemiJSON
internal import AskAI

extension ToolSummary {
    /// The skill tool's input, as it reads it: a name loads, otherwise the query searches and an empty one browses.
    private struct SkillFields: Decodable {
        let name: String?
        let query: String?
        let from: Words?
    }

    /// `from` as the tool takes it: one word, or a list of them.
    private struct Words: Decodable {
        let list: [String]

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            list = try (try? value.decode(String.self)).map { [$0] } ?? value.decode([String].self)
        }
    }

    /// `pdf`, `search · swift testing` or `browse`, then `· from project, codex` when the call narrows its sources; nil when the
    /// input is not the skill tool's, so the caller falls back to the input itself.
    static func skillHeader(for input: JSONObject) -> String? {
        guard let fields = try? AemiJSON.JSONDecoder().decode(SkillFields.self, from: input.bytes) else { return nil }
        let query = fields.query.map(compact) ?? ""
        var parts = [fields.name.map(compact) ?? (query.isEmpty ? "browse" : "search · \(query)")]
        if let from = fields.from?.list, !from.isEmpty { parts.append("from " + from.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
