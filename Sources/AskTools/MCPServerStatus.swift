/// Where one configured server stands (`/mcp` shows these).
public struct MCPServerStatus: Sendable, Equatable {
    /// What has become of the server.
    public enum State: Sendable, Equatable {
        /// Configured off; never started.
        case off
        /// Starting, or listing its tools.
        case connecting
        /// Connected; `offered` of its `of` tools are offered to the model.
        case ready(offered: Int, of: Int)
        /// Connected, with too many tools to list: they are reached through the two search tools.
        case searchable(tools: Int)
        /// Not connected, and why.
        case failed(String)
    }

    /// The name the configuration gave it.
    public let name: String
    public var state: State
    /// Things worth saying that are not the state, such as a listed tool the server does not have.
    public var notes: [String] = []

    /// What a one-shot run says about a server that is not working, or nil when there is nothing to say.
    public var problem: String? {
        switch state {
            case .failed(let reason): "MCP server \(name) did not start: \(reason)"
            case .off, .connecting, .ready, .searchable: nil
        }
    }

    /// What is worth saying about a server that works but not the plain way, or nil.
    public var remark: String? {
        guard case .searchable(let tools) = state else { return nil }
        return "MCP server \(name) has \(tools) tools: they are searched with mcp_search and called with mcp_call. "
            + "Name the ones you want in mcp.\(name).tools to offer them directly."
    }
}
