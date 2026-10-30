extension SettingCatalog {
    /// `docs/config.example.jsonc`: every setting, nested as a file writes it, each under a comment with its help, its default and
    /// whether only your own file may set it; and one MCP server. ask reads comments (JSON5), so the file loads as it is.
    static var example: String {
        var lines = [
            "// Every setting ask reads, with an example value. Generated from Sources/AskAgentCore/Configuration/SettingCatalog.swift:",
            "// do not edit; `ASK_WRITE_EXAMPLE=1 swift test --filter SettingCatalogTests` writes it again.",
            "// Copy only what you want to change into ~/.config/ask/config.json; see docs/configuration.md.",
            "{"
        ]
        var body = members(of: all.map { ($0.path, $0) }, depth: 1)
        body[body.count - 1] += ","  // `mcp` follows
        lines += body
        lines += [
            "", "  // MCP servers whose tools are offered to the model, by name (docs/skills-and-mcp.md).",
            "  \"mcp\": {", "    \"docs\": {\"url\": \"https://example.com/mcp\", \"enabled\": false}", "  }", "}"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The object holding `entries`, whose paths are relative to it: a key per first component, in the order they first appear.
    private static func members(of entries: [([String], Setting)], depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var order: [String] = []
        var groups: [String: [([String], Setting)]] = [:]
        for (path, setting) in entries {
            if groups[path[0]] == nil { order.append(path[0]) }
            groups[path[0], default: []].append((Array(path.dropFirst()), setting))
        }
        var lines: [String] = []
        for (position, key) in order.enumerated() {
            let group = groups[key] ?? []
            let comma = position == order.count - 1 ? "" : ","
            if let (rest, setting) = group.first, rest.isEmpty {
                if depth == 1 || position > 0 { lines.append("") }
                lines.append(indent + "// " + comment(setting))
                lines.append(indent + "\"\(key)\": \(setting.example)\(comma)")
            } else {
                if position > 0 { lines.append("") }
                lines.append(indent + "\"\(key)\": {")
                lines += members(of: group, depth: depth + 1)
                lines.append(indent + "}\(comma)")
            }
        }
        return lines
    }

    private static func comment(_ setting: Setting) -> String {
        var text = "\(setting.help) Default: \(setting.defaultValue)."
        if case .choice(let words) = setting.kind { text += " One of: " + words.joined(separator: ", ") + "." }
        if setting.userOnly { text += " Your own file only." }
        return text
    }
}
