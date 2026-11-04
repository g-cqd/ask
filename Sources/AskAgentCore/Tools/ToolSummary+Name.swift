internal import AemiJSON
public import AskAI

/// The name a tool's block is headed with (note n25): a server's tool as `server/tool`, not the wire name a provider needs.
extension ToolSummary {
    private struct Dispatched: Decodable {
        let server: String?
        let tool: String?
    }

    /// `name` as the person reads it: `bash` as `shell`; `mcp__server__tool` as `server/tool`; a `dispatch_call` as the server's tool
    /// it calls, from its input. Anything else is its own name. The session keeps the wire name; only what is shown changes.
    public static func shownName(_ name: String, input: JSONObject? = nil) -> String {
        if name == "bash" { return "shell" }
        let prefix = "mcp__"
        if name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count)
            if let split = rest.firstRange(of: "__"), !rest[..<split.lowerBound].isEmpty,
                !rest[split.upperBound...].isEmpty
            {
                return rest[..<split.lowerBound] + "/" + rest[split.upperBound...]
            }
        }
        if name == "dispatch_call", let input,
            let called = try? AemiJSON.JSONDecoder().decode(Dispatched.self, from: input.bytes),
            let server = called.server, let tool = called.tool, !server.isEmpty, !tool.isEmpty
        {
            return server + "/" + tool
        }
        return name
    }
}
