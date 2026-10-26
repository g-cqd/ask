internal import AemiJSON
public import AskAI

/// The one line that shows a tool call on a screen or in a log (roadmap 0028).
public enum ToolSummary {
    /// The most characters of the line that are shown.
    static let maximumCharacters = 160

    /// The command or the path of a call when it has one, else its whole input: only the first line, cut at 160 characters with `…`.
    /// - Parameter input: the call's input.
    /// - Returns: the line.
    public static func line(for input: JSONObject) -> String {
        struct Fields: Decodable {
            let command: String?
            let path: String?
        }
        let fields = try? AemiJSON.JSONDecoder().decode(Fields.self, from: input.bytes)
        let summary = fields?.command ?? fields?.path ?? String(decoding: input.bytes, as: UTF8.self)
        let firstLine = summary.split(separator: "\n").first.map(String.init) ?? summary
        return firstLine.count > maximumCharacters ? String(firstLine.prefix(maximumCharacters)) + "…" : firstLine
    }
}
