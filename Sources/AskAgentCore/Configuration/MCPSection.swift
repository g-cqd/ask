internal import Foundation

/// The `mcp` section of a configuration file: the servers whose tools the model may use (ADR-0099). Naming a server runs a program, so a
/// project's file counts only once the person has trusted it, and trusting it says what would start (``consent``).
public struct MCPSection: Sendable, Equatable, CustomStringConvertible {
    /// The servers, sorted by name.
    public var servers: [MCPServerSetting]
    /// Changes to servers a lower file defines, sorted by name (roadmap 0127); applied by ``layered(with:)``.
    public var masks: [MCPServerMask]

    /// A section of these servers and changes.
    public init(servers: [MCPServerSetting] = [], masks: [MCPServerMask] = []) {
        self.servers = servers.sorted { $0.name < $1.name }
        self.masks = masks.sorted { $0.name < $1.name }
    }

    public var isEmpty: Bool { servers.isEmpty && masks.isEmpty }

    /// `self` with every server `section` defines replaced whole, the others kept, and then `section`'s changes applied to the servers
    /// they name; a change naming no server is dropped (the loader says so).
    public func layered(with section: MCPSection) -> MCPSection {
        let replaced = Set(section.servers.map(\.name))
        let masks = Dictionary(section.masks.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        let kept = servers.filter { !replaced.contains($0.name) } + section.servers
        return MCPSection(servers: kept.map { server in masks[server.name]?.applied(to: server) ?? server })
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

    /// What trusting a file with these servers would start or connect to, a line each, so that consent is to something said: the program
    /// and its arguments, or the address without its query or credentials. Never an environment value or a header.
    public var consent: [String] {
        servers.map { server in
            let off = server.enabled ? "" : " (off)"
            if let command = server.command {
                return "\(server.name): runs \(([command] + server.args).joined(separator: " "))\(off)"
            }
            let address = server.url.flatMap(Self.withoutQuery) ?? "an address that does not parse"
            return "\(server.name): connects to \(address)\(off)"
        } + masks.map { "\($0.name): changes your server: \($0.changes)" }
    }

    private static func withoutQuery(_ address: String) -> String? {
        guard var parts = URLComponents(string: address) else { return nil }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.string
    }
}
