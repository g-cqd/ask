internal import AskMCP

/// The text a resource listing gives the model: each resource's URI, name and description, at most ``maximum`` of them, and every template.
enum MCPResourceListing {
    static let maximum = 100
    private static let descriptionLength = 100

    static func text(server: String, resources: [MCPResource], templates: [MCPResourceTemplate]) -> String {
        var lines: [String] = []
        if resources.isEmpty {
            lines.append("\(server) lists no resources.")
        } else {
            let shown = resources.prefix(maximum)
            lines.append("Resources of \(server) (\(resources.count)):")
            lines += shown.map { line($0.uri, $0.title ?? $0.name, $0.description) }
            if resources.count > shown.count {
                lines.append(
                    "\(resources.count - shown.count) more, not shown: read one by its URI, or through a template."
                )
            }
        }
        if !templates.isEmpty {
            lines.append("Templates (fill in each {…} to make a URI):")
            lines += templates.map { line($0.uriTemplate, $0.name, $0.description) }
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ uri: String, _ name: String, _ description: String?) -> String {
        let words = description.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        let cut = words.map { $0.count > descriptionLength ? $0.prefix(descriptionLength - 1) + "…" : $0 }
        return "- \(uri)  \(name)" + (cut.map { " — \($0)" } ?? "")
    }
}
