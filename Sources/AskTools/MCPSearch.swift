internal import AskAI
internal import AskMCP
internal import Foundation

/// Finding a tool among those of servers too large to list (ADR-0100): by the words of a tool's name and description.
enum MCPSearch {
    /// A tool of a server, as the search sees it.
    struct Candidate: Equatable {
        let server: String
        let tool: MCPTool
    }

    /// The bytes of schema a search shows in all, and the least it shows of any one tool.
    static let schemaBudget = 12_000
    static let schemaMinimum = 3000

    /// How much of each schema to show when there are `count` matches: the budget shared out, never less than the minimum, so a search
    /// that names one tool shows nearly all of its schema (a cut before its `$defs` leaves references nothing can resolve).
    static func schemaBytes(forMatches count: Int) -> Int { max(schemaMinimum, schemaBudget / max(1, count)) }

    /// The most characters of a description that are shown.
    static let descriptionCharacters = 300

    /// The candidates that have any of the words of `query`, the best first.
    ///
    /// A word in a tool's name counts three and one in its description counts one, whether the word is the whole of a part or only in it
    /// (`function` finds `list_functions`). Ties keep the order of `candidates`. With no words, everything is a match, in order.
    /// - Parameters:
    ///   - candidates: every tool there is to search.
    ///   - query: the words.
    ///   - server: only this server's, or nil for all.
    ///   - limit: the most to return.
    /// - Returns: at most `limit` candidates.
    static func rank(_ candidates: [Candidate], query: String, server: String?, limit: Int) -> [Candidate] {
        let words = Self.words(query)
        let pool = candidates.filter { server == nil || $0.server == server }
        guard !words.isEmpty else { return Array(pool.prefix(limit)) }
        let scored = pool.enumerated()
            .compactMap { index, candidate -> (Int, Int, Candidate)? in
                let name = candidate.tool.name.lowercased()
                let description = candidate.tool.description.lowercased()
                let score = words.reduce(0) { total, word in
                    total + (name.contains(word) ? 3 : 0) + (description.contains(word) ? 1 : 0)
                }
                return score > 0 ? (score, index, candidate) : nil
            }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.prefix(limit).map(\.2)
    }

    /// What the model reads of the matches: for each, the server and tool, what it does, and the schema of its arguments, which is
    /// what a call needs. A schema longer than `schemaBytes` is cut, and the cut is said.
    static func describe(_ matches: [Candidate], schemaBytes: Int) -> String {
        matches.map { match in
            let schema = match.tool.inputSchema.bytes
            let shown = String(decoding: schema.prefix(schemaBytes), as: UTF8.self)
            let cut = schema.count > schemaBytes ? " (schema cut at \(schemaBytes) of \(schema.count) bytes)" : ""
            var description = match.tool.description
            if description.count > descriptionCharacters {
                description = String(description.prefix(descriptionCharacters)) + "…"
            }
            return "\(match.server) / \(match.tool.name)\n  \(description)\n  arguments\(cut): \(shown)"
        }
        .joined(separator: "\n\n")
    }

    /// The tools' names by server, for browsing: `server: a, b, c`, a line each.
    static func names(_ candidates: [Candidate]) -> String {
        var order: [String] = []
        var byServer: [String: [String]] = [:]
        for candidate in candidates {
            if byServer[candidate.server] == nil { order.append(candidate.server) }
            byServer[candidate.server, default: []].append(candidate.tool.name)
        }
        return order.map { "\($0): \(byServer[$0, default: []].joined(separator: ", "))" }.joined(separator: "\n")
    }

    private static func words(_ query: String) -> [String] {
        query.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
