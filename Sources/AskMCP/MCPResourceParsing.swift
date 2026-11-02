internal import AemiJSON

/// Reads a server's resources, templates and contents: what has the wrong shape is skipped, and nothing here throws.
enum MCPResourceParsing {
    // @dl:accept -- a resource and a template are read alike, each into its own type: the protocol's two shapes
    static func resource(_ element: JSON) -> MCPResource? {
        guard element.isObject, let uri = element["uri"].string, !uri.isEmpty else { return nil }
        return MCPResource(
            uri: uri,
            name: element["name"].string ?? uri,
            // @dl:accept -- the optional fields of a resource and of a template have the same names in the protocol
            title: element["title"].string,
            description: element["description"].string,
            mimeType: element["mimeType"].string
        )
    }

    static func template(_ element: JSON) -> MCPResourceTemplate? {
        guard element.isObject, let pattern = element["uriTemplate"].string, !pattern.isEmpty else { return nil }
        return MCPResourceTemplate(
            uriTemplate: pattern,
            name: element["name"].string ?? pattern,
            description: element["description"].string,
            mimeType: element["mimeType"].string
        )
    }

    /// A part of a read: text, or a blob; a part with neither is skipped.
    static func contents(_ element: JSON) -> MCPResourceContents? {
        guard element.isObject, let uri = element["uri"].string else { return nil }
        let body: MCPResourceContents.Body
        if let text = element["text"].string {
            body = .text(text)
        } else if let blob = element["blob"].string {
            body = .blob(base64: blob)
        } else {
            return nil
        }
        return MCPResourceContents(uri: uri, mimeType: element["mimeType"].string, body: body)
    }
}
