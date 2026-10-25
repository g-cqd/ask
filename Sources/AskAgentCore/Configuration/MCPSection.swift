/// The `mcp` section of a configuration file: the servers whose tools the model may use (ADR-0099). Only the user's own file may have
/// one, because naming a server runs a program.
public struct MCPSection: Sendable, Equatable, CustomStringConvertible {
    /// The servers, sorted by name.
    public var servers: [MCPServerSetting]

    /// A section of these servers.
    public init(servers: [MCPServerSetting] = []) { self.servers = servers.sorted { $0.name < $1.name } }

    public var isEmpty: Bool { servers.isEmpty }

    /// `self` with every server `section` names replaced whole, and the others kept.
    public func layered(with section: MCPSection) -> MCPSection {
        let replaced = Set(section.servers.map(\.name))
        return MCPSection(servers: servers.filter { !replaced.contains($0.name) } + section.servers)
    }

    /// The servers and how each is reached, and never what it was given: environment and headers can hold secrets.
    public var description: String {
        servers.isEmpty
            ? "none"
            : servers.map { server in
                "\(server.name) (\(server.command == nil ? "url" : "command")\(server.enabled ? "" : ", off"))"
            }
            .joined(separator: ", ")
    }
}
