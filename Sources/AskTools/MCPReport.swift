/// What `/mcp` shows (ADR-0099): one line a server, with its notes under it.
enum MCPReport {
    /// The lines for `statuses`, or how to add a server when there are none.
    static func lines(_ statuses: [MCPServerStatus]) -> [String] {
        guard !statuses.isEmpty else {
            return [
                "No MCP servers are configured. Name them under \"mcp\" in your config file (ask config shows where)."
            ]
        }
        return statuses.flatMap { status in
            ["\(status.name): \(describe(status.state))"] + (status.notes + hints(status)).map { "    \($0)" }
        }
    }

    /// How to change what a server offers, where the plain way does not apply: a searched server's tools, offered whole by name.
    private static func hints(_ status: MCPServerStatus) -> [String] {
        guard case .searchable = status.state else { return [] }
        return ["name the ones you want in mcp.\(status.name).tools to offer them directly"]
    }

    private static func describe(_ state: MCPServerStatus.State) -> String {
        switch state {
            case .off: "off (enabled is false in the configuration)"
            case .connecting: "connecting…"
            case .ready(let offered, let total): "ready, \(offered) of \(total) tool\(total == 1 ? "" : "s") offered"
            case .searchable(let tools): "ready, \(tools) tools reachable through mcp_search and mcp_call"
            case .failed(let reason): "not connected: \(reason)"
        }
    }
}
