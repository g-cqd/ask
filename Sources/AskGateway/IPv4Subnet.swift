internal import Darwin

/// IPv4 address and CIDR checks for the gateway's nodes door (ADR-0170): the door must bind a specific interface address (never
/// `0.0.0.0`), and may further restrict peers to an IPv4 CIDR block before any handshake byte is read.
package struct IPv4Subnet: Sendable, Equatable {
    private let network: UInt32
    private let mask: UInt32

    /// Parses `cidr` such as `"192.168.1.0/24"` or a single host `"192.168.1.10/32"`.
    package init?(_ cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let prefix = Int(parts[1]), (0 ... 32).contains(prefix),
            let address = Self.ipv4(String(parts[0]))
        else { return nil }
        mask = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        network = address & mask
    }

    /// Whether `address` (host byte order) lies inside this subnet.
    package func contains(_ address: UInt32) -> Bool { (address & mask) == network }

    /// Parses a dotted IPv4 address into host byte order; nil when malformed.
    package static func ipv4(_ text: String) -> UInt32? {
        var raw = in_addr()
        guard inet_pton(AF_INET, text, &raw) == 1 else { return nil }
        return UInt32(bigEndian: raw.s_addr)
    }

    /// Whether `host` is a specific, non-wildcard IPv4 address suitable for the nodes door (`0.0.0.0` is refused).
    package static func isSpecificBindAddress(_ host: String) -> Bool {
        guard let address = ipv4(host) else { return false }
        return address != 0
    }

    /// The peer's IPv4 address (host byte order) of connected socket `descriptor`; nil if unavailable.
    package static func peerAddress(of descriptor: Int32) -> UInt32? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe getpeername(descriptor, $0, &length) == 0
            }
        }
        guard ok, address.sin_family == sa_family_t(AF_INET) else { return nil }
        return UInt32(bigEndian: address.sin_addr.s_addr)
    }
}
