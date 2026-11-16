internal import AemiJSON

/// An MCP server a client gives a session (ACP v1, Session Setup, "MCP servers"): a program to start, or an address to speak
/// to over HTTP. Its `env` and `headers` are credentials: they are passed on to what starts the server and said nowhere.
package struct ACPMCPServer: Sendable, Equatable {
    /// The client's name for it, which is for a person to read.
    package let name: String
    /// The program, for a server the agent starts, and its arguments.
    package let command: String?
    package let args: [String]
    package let env: [String: String]
    /// The address, for a server spoken to over HTTP, and the header fields sent to it.
    package let url: String?
    package let headers: [String: String]

    /// What `mcpServers` of a `session/new` or a `session/load` names: the servers that can be run, and for each that cannot
    /// a line saying why, which names the server and none of its values. One entry that cannot be run does not cost the
    /// client its session, nor the other servers.
    static func servers(of params: JSON?) -> (servers: [ACPMCPServer], unusable: [String]) {
        guard let listed = params?["mcpServers"].array else { return ([], []) }
        var servers: [ACPMCPServer] = []
        var unusable: [String] = []
        for (index, entry) in listed.enumerated() {
            let name = entry["name"].string ?? ""
            let called = name.isEmpty ? "The MCP server at place \(index + 1)" : "The MCP server \(name)"
            switch entry["type"].string {
                case nil, "stdio"?:
                    guard let command = entry["command"].string, !command.isEmpty else {
                        unusable.append("\(called) names no command: it is not started.")
                        continue
                    }
                    let args = entry["args"].array?.compactMap(\.string) ?? []
                    servers.append(
                        ACPMCPServer(
                            name: name,
                            command: command,
                            args: args,
                            env: pairs(entry["env"]),
                            url: nil,
                            headers: [:]
                        )
                    )
                case "http"?:
                    guard let url = entry["url"].string, !url.isEmpty else {
                        unusable.append("\(called) names no address: it is not connected to.")
                        continue
                    }
                    servers.append(
                        ACPMCPServer(
                            name: name,
                            command: nil,
                            args: [],
                            env: [:],
                            url: url,
                            headers: pairs(entry["headers"])
                        )
                    )
                case "sse"?:
                    unusable.append("\(called) is spoken to over SSE, which ask does not: it is not connected to.")
                case let other?:
                    unusable.append("\(called) is of a kind ask does not know (\(other)): it is not connected to.")
            }
        }
        return (servers, unusable)
    }

    /// `[{"name": …, "value": …}]` as a table; an entry without both is left out.
    private static func pairs(_ list: JSON) -> [String: String] {
        var table: [String: String] = [:]
        for entry in list.array ?? [] {
            if let name = entry["name"].string, let value = entry["value"].string { table[name] = value }
        }
        return table
    }
}
