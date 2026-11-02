internal import AemiJSON

extension MCPConnection {
    /// Every resource the server lists, following its pages.
    /// - Throws: ``MCPError/tooManyPages`` if the listing never ends, or whatever a request throws.
    public func listResources() async throws(MCPError) -> [MCPResource] {
        try await paged("resources/list", key: "resources", MCPResourceParsing.resource)
    }

    /// Every resource template the server offers, following its pages.
    public func listResourceTemplates() async throws(MCPError) -> [MCPResourceTemplate] {
        try await paged("resources/templates/list", key: "resourceTemplates", MCPResourceParsing.template)
    }

    /// Reads the resource at `uri`: its parts, each text or base64 bytes.
    public func readResource(_ uri: String) async throws(MCPError) -> [MCPResourceContents] {
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { MCPWire.put(&$0, "uri", string: uri) }
        let reply = try await request("resources/read", params: writer.finish(), timeout: requestTimeout)
        var parts: [MCPResourceContents] = []
        reply["contents"].forEachElement { if let part = MCPResourceParsing.contents($0) { parts.append(part) } }
        return parts
    }

    /// Asks to be told when the resource at `uri` changes (``MCPEvent/resourceUpdated(uri:)``); only for a server that offers it.
    public func subscribe(to uri: String) async throws(MCPError) {
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { MCPWire.put(&$0, "uri", string: uri) }
        _ = try await request("resources/subscribe", params: writer.finish(), timeout: requestTimeout)
    }

    /// A listing of `method`, its items under `key`, read by `parse`, page after page.
    private func paged<Item>(_ method: String, key: String, _ parse: (JSON) -> Item?) async throws(MCPError) -> [Item] {
        var items: [Item] = []
        var cursor: String?
        for _ in 0 ..< Self.maximumListPages {
            let reply = try await request(method, params: cursor.map(Self.cursorParams), timeout: requestTimeout)
            reply[key].forEachElement { if let item = parse($0) { items.append(item) } }
            guard let next = reply["nextCursor"].string, !next.isEmpty else { return items }
            cursor = next
        }
        throw .tooManyPages
    }
}
