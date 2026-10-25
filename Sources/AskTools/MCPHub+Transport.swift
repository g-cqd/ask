internal import AskAI
internal import AskAgentCore
internal import AskMCP
internal import Foundation

extension MCPHub {
    /// What ask names itself to a server. Some servers' front doors refuse a client that names nothing.
    public static let userAgent = "ask/0 (MCP client)"

    /// The real transports: a child process for a server with a `command`, and an HTTPS connection for one with a `url`.
    /// - Parameter inheriting: the environment a child's minimal one is taken from (ADR-0096): ask's own.
    /// - Returns: the factory a hub is made with.
    public static func standardTransport(inheriting: [String: String]) -> MCPHost.TransportFactory {
        { server, environment, headers in
            if let command = server.command {
                return StdioTransport(
                    StdioLaunch(
                        executable: command, arguments: server.args, environment: environment,
                        workingDirectory: server.cwd, inheriting: inheriting))
            }
            guard let address = server.url, let url = URL(string: address) else {
                throw MCPError.refusedEndpoint("the setting has no usable address")
            }
            return try HTTPMCPTransport(
                url: url, headers: headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) },
                userAgent: userAgent, http: URLSessionTransport())
        }
    }
}
