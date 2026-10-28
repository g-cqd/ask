internal import AemiJSON
internal import AskAI

/// Reads a server's tools and results, which are the server's text and may be anything: what is missing is defaulted, what is the
/// wrong shape is skipped, and nothing here throws.
enum MCPToolParsing {
    /// One element of a tool listing, or nil when it is not a tool.
    static func tool(_ element: JSON) -> MCPTool? {
        guard element.isObject, let name = element["name"].string, !name.isEmpty else { return nil }
        let schema =
            element["inputSchema"].isObject
            ? element["inputSchema"].withRawJSONBytes { try? JSONObject(validating: Array($0)) } ?? nil
            : nil
        let hints = element["annotations"]
        return MCPTool(
            name: name, title: element["title"].string, description: element["description"].string ?? "",
            inputSchema: schema ?? (try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8))),
            annotations: MCPToolAnnotations(
                readOnly: hints["readOnlyHint"].bool, destructive: hints["destructiveHint"].bool,
                idempotent: hints["idempotentHint"].bool, openWorld: hints["openWorldHint"].bool),
            hasOutputSchema: element["outputSchema"].isObject)
    }

    /// A `tools/call` result, read from the object the envelope already parsed (it is always an object there).
    static func result(_ root: JSON) -> MCPToolResult {
        var content: [MCPContent] = []
        root["content"].forEachElement { content.append(block($0)) }
        let structured = root["structuredContent"]
        return MCPToolResult(
            content: content, structuredContent: structured.isObject ? structured.withRawJSONBytes { Array($0) } : nil,
            isError: root["isError"].bool ?? false)
    }

    /// One block of a result.
    private static func block(_ element: JSON) -> MCPContent {
        let type = element["type"].string ?? ""
        switch type {
            case "text": return .text(element["text"].string ?? "")
            case "image":
                return .image(mimeType: element["mimeType"].string ?? "", base64: element["data"].string ?? "")
            case "audio":
                return .audio(mimeType: element["mimeType"].string ?? "", base64: element["data"].string ?? "")
            case "resource_link":
                return .resourceLink(
                    uri: element["uri"].string ?? "", name: element["name"].string, mimeType: element["mimeType"].string
                )
            case "resource":
                let resource = element["resource"]
                return .resource(
                    uri: resource["uri"].string ?? "", mimeType: resource["mimeType"].string,
                    text: resource["text"].string)
            default: return .unknown(type: type)
        }
    }
}
