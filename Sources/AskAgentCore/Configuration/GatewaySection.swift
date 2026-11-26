internal import Foundation

/// The `gateway` section of a configuration file (ADR-0170): whether this computer shares its sessions with a gateway, where the
/// gateway is, the key it must hold, and the folders a controller may start a session in. The person's own file only: a project
/// cannot share sessions.
public struct GatewaySection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `gateway.enabled`: whether this computer offers its sessions to the gateway.
    public var enabled: Bool?
    /// `gateway.address`: the gateway on the local network, `host:port`.
    public var address: String?
    /// `gateway.key`: the gateway's public key, base64; a gateway holding another is refused.
    public var key: String?
    /// `gateway.folders`: the folders a controller may start a session in, absolute or under `~/`.
    public var folders: [String]?

    public init() {}

    /// The keys, in the order they are shown, from their declarations (``GatewaySection/settings``).
    public static let keys = settings.all.map(\.name)

    /// Whether sharing is on: `enabled`, with an address and a key to reach the gateway by.
    public var isSharing: Bool { enabled == true && address != nil && key != nil }

    public var description: String { Self.settings.describe(self) }

    /// `host:port` split, the port 1 to 65,535 and the host not empty; nil otherwise. A host in brackets is an IPv6 address.
    public static func endpoint(_ written: String) -> (host: String, port: Int)? {
        guard let colon = written.lastIndex(of: ":"), let port = Int(written[written.index(after: colon)...]),
            (1 ... 65_535).contains(port)
        else { return nil }
        var host = String(written[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        return (host, port)
    }

    /// Whether `written` is a 32-byte key in base64.
    public static func isKey(_ written: String) -> Bool { Data(base64Encoded: written)?.count == 32 }
}
