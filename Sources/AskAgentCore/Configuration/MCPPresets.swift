/// Sets of MCP servers ask knows by a name (the owner's choice, 2026-11-02, roadmap 0190): `"presets": ["swift"]` in a file adds their
/// servers to that file's `mcp`, as if it named them, so a project's file goes through the trust its own servers do.
enum MCPPresets {
    /// Each preset's servers.
    static let known: [String: [MCPServerSetting]] = [
        // Apple's documentation, from the public apple-docs instance, and the workspace's Swift code, from a local swift-search.
        "swift": [
            MCPServerSetting(name: "apple-docs", url: "https://apple-docs-mcp.everest.mt/mcp"),
            MCPServerSetting(name: "swift-search", command: "swift-search", args: ["mcp"])
        ]
    ]

    /// `section` with the servers of `presets` added: a server the file names itself wins, and a change the file makes to a preset's
    /// server (`enabled: false`, say) is applied to it.
    /// - Parameters:
    ///   - presets: the names the file lists.
    ///   - section: the file's own `mcp`.
    ///   - path: the file, for the error.
    /// - Returns: the section, or nil when there is nothing in it.
    /// - Throws: `ConfigurationError.outOfRange` for a name ask does not know.
    static func adding(_ presets: [String]?, to section: MCPSection?, path: String) throws(ConfigurationError)
        -> MCPSection?
    {
        guard let presets, !presets.isEmpty else { return section }
        let own = section ?? MCPSection()
        var servers = own.servers
        var masks = own.masks
        for name in presets {
            guard let added = known[name] else {
                let names = known.keys.sorted().joined(separator: ", ")
                throw .outOfRange(path: path, key: "presets", reason: "\"\(name)\" is not a preset ask knows: \(names)")
            }
            for server in added where !servers.contains(where: { $0.name == server.name }) {
                let change = masks.firstIndex { $0.name == server.name }
                servers.append(change.map { masks[$0].applied(to: server) } ?? server)
                if let change { masks.remove(at: change) }
            }
        }
        let result = MCPSection(servers: servers, masks: masks)
        return result.isEmpty ? nil : result
    }
}
