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
        /// Connected, and none of its tools are offered, and why.
        case skipped(String)
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
            case .skipped(let reason): "MCP server \(name) \(reason); none of its tools are offered"
            case .off, .connecting, .ready: nil
        }
    }
}
