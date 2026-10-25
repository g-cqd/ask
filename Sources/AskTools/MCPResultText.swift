internal import AskMCP

/// A tool's result as the text the model reads (ADR-0099). Text is passed on as it is; what a terminal agent cannot use is named, with
/// its type and size, and never pasted: a base64 image would be tens of thousands of tokens of nothing.
enum MCPResultText {
    /// The text of `result`.
    static func of(_ result: MCPToolResult) -> String {
        let parts = result.content.map(text).filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: "\n\n") }
        if let structured = result.structuredContent, !structured.isEmpty {
            return String(decoding: structured, as: UTF8.self)
        }
        return "(the tool returned nothing)"
    }

    private static func text(_ block: MCPContent) -> String {
        switch block {
            case .text(let text): text
            case .image(let type, let data): "[image \(type), \(size(ofBase64: data)) bytes: ask cannot show it]"
            case .audio(let type, let data): "[audio \(type), \(size(ofBase64: data)) bytes: ask cannot play it]"
            case .resourceLink(let uri, let name, _): "[resource \(name ?? uri): \(uri)]"
            case .resource(let uri, let type, let text):
                text ?? "[resource \(uri)\(type.map { " (\($0))" } ?? ""): no text]"
            case .unknown(let type): "[a \(type) block that ask does not understand]"
        }
    }

    /// The bytes `data` stands for, without decoding it.
    private static func size(ofBase64 data: String) -> Int {
        let padding = data.reversed().prefix { $0 == "=" }.count
        return max(0, data.utf8.count * 3 / 4 - padding)
    }
}
