/// What MCP startup says, once, in one block (roadmap 0145): how many servers connected, and each one that failed with its reason. What
/// each server offers, and how a big one's tools are searched, is in `/mcp`.
enum MCPStartupSummary {
    /// The block for `statuses`, or nil when there is nothing to say yet or at all: no server is on, or one is still connecting.
    static func text(_ statuses: [MCPServerStatus]) -> String? {
        var connected = 0
        var failures: [String] = []
        for status in statuses {
            switch status.state {
                case .off: continue
                case .connecting: return nil
                case .ready, .searchable: connected += 1
                case .failed(let reason): failures.append("  \(status.name): \(reason)")
            }
        }
        guard connected + failures.count > 0 else { return nil }
        let head =
            connected == 0
            ? "No MCP server connected."
            : "\(connected) MCP server\(connected == 1 ? "" : "s") connected."
        guard !failures.isEmpty else { return head }
        return head + " \(failures.count) failed to connect:\n" + failures.joined(separator: "\n")
    }
}
