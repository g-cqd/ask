internal import AskAI
internal import AskAgentCore
internal import AskMCP
internal import Synchronization

/// The tools of the servers that are searched, not listed (ADR-0100), with the connection each is called through.
final class MCPCatalog: Sendable {
    private struct Entry {
        var server: String
        var tools: [MCPTool]
        var connection: MCPConnection
    }

    private let entries = Mutex<[Entry]>([])
    // LiveTools holds the search tool, which holds this catalog: do not close that ownership cycle.
    private let publish: @Sendable (String, [any Tool]) -> Void

    init(live: LiveTools? = nil) {
        publish = { [weak live] group, tools in live?.replace(group: group, with: tools) }
    }

    /// Replaces each matched server's promoted set, at most eight tools, validated against its current listing.
    /// Listing changes and disconnects share this lock, so a stale search cannot resurrect a withdrawn adapter.
    func promote(_ matches: [MCPSearch.Candidate]) {
        entries.withLock { entries in
            for server in Set(matches.map(\.server)) {
                guard let entry = entries.first(where: { $0.server == server }) else { continue }
                let current = matches.filter { $0.server == server && entry.tools.contains($0.tool) }.prefix(8)
                publish(
                    server + "/promoted",
                    current.map {
                        MCPToolAdapter(
                            server: server, tool: $0.tool,
                            name: MCPToolName.make(server: server, tool: $0.tool.name), connection: entry.connection
                        )
                    })
            }
        }
    }

    /// Makes `tools` all there is of `server`.
    func set(server: String, tools: [MCPTool], connection: MCPConnection) {
        entries.withLock { entries in
            publish(server + "/promoted", [])
            if let index = entries.firstIndex(where: { $0.server == server }) {
                entries[index] = Entry(server: server, tools: tools, connection: connection)
            } else {
                entries.append(Entry(server: server, tools: tools, connection: connection))
            }
        }
    }

    /// Forgets `server`.
    func remove(server: String) {
        entries.withLock { entries in
            entries.removeAll { $0.server == server }
            publish(server + "/promoted", [])
        }
    }

    /// Every server and how many tools it has, in the order they arrived.
    var servers: [(name: String, tools: Int)] { entries.withLock { $0.map { ($0.server, $0.tools.count) } } }

    /// Every tool of every server.
    var candidates: [MCPSearch.Candidate] {
        entries.withLock {
            $0.flatMap { entry in entry.tools.map { MCPSearch.Candidate(server: entry.server, tool: $0) } }
        }
    }

    /// The connection `server` is called through and the tool itself, if the server is here and has a tool called `name`.
    func find(server: String, tool name: String) -> (connection: MCPConnection, tool: MCPTool)? {
        entries.withLock { entries in
            guard let entry = entries.first(where: { $0.server == server }),
                let tool = entry.tools.first(where: { $0.name == name })
            else { return nil }
            return (entry.connection, tool)
        }
    }
}
