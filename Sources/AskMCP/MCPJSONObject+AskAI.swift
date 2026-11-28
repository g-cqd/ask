public import AemiMCP
public import AskAI

extension MCPJSONObject {
    /// `object` for an MCP server: a tool's arguments as the model gave them. Validated again, which costs one parse of
    /// the arguments per call; nil only if `object`'s bytes were not one JSON object, which `JSONObject` rules out.
    public init?(_ object: JSONObject) {
        guard let converted = try? MCPJSONObject(validating: object.bytes) else { return nil }
        self = converted
    }
}
