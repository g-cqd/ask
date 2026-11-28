public import AemiMCP
public import AskAI

extension JSONObject {
    /// `object` from an MCP server, such as a tool's input schema; nil only if its bytes were not one JSON object, which
    /// `MCPJSONObject` rules out.
    public init?(_ object: MCPJSONObject) {
        guard let converted = try? JSONObject(validating: object.bytes) else { return nil }
        self = converted
    }
}
