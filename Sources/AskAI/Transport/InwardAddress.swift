internal import Darwin

/// Whether an address literal reaches inward rather than the public internet (security audit 2026-11-22, CRIT-05): read as bytes
/// with `inet_pton`, in any spelling, against RFC 6890's ranges that are not globally reachable. A request a remote party can steer
/// (a page fetched, an MCP server's metadata) is refused such an address unless the person named this machine themselves.
public enum InwardAddress {
    /// Whether `literal` is an IPv4 or IPv6 address (brackets allowed) in a loopback, private, link-local, shared, reserved,
    /// documentation, benchmarking, multicast or unspecified range, or an IPv6 form that carries such an IPv4 address. Not an
    /// address at all: false, for a name is judged by what it resolves to.
    public static func contains(_ literal: String) -> Bool {
        var bare = Substring(literal)
        if bare.hasPrefix("["), bare.hasSuffix("]") { bare = bare.dropFirst().dropLast() }
        if let zone = bare.firstIndex(of: "%") { bare = bare[..<zone] }
        var v4 = in_addr()
        if inet_pton(AF_INET, String(bare), &v4) == 1 {
            return inwardV4(withUnsafeBytes(of: v4.s_addr) { Array($0) })
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, String(bare), &v6) == 1 else { return false }
        return inwardV6(withUnsafeBytes(of: v6) { Array($0) })
    }

    private static func inwardV4(_ bytes: [UInt8]) -> Bool {
        let (first, second) = (bytes[0], bytes[1])
        switch first {
            case 0, 10, 127: return true
            case 100: return (64 ... 127).contains(second)  // shared address space
            case 169: return second == 254
            case 172: return (16 ... 31).contains(second)
            // private, IETF, documentation
            case 192: return second == 168 || (second == 0 && (bytes[2] == 0 || bytes[2] == 2))
            // benchmarking, documentation
            case 198: return second == 18 || second == 19 || (second == 51 && bytes[2] == 100)
            case 203: return second == 0 && bytes[2] == 113  // documentation
            default: return first >= 224  // multicast, reserved, broadcast
        }
    }

    private static func inwardV6(_ bytes: [UInt8]) -> Bool {
        let zeros = bytes[0 ..< 10].allSatisfy { $0 == 0 }
        // ::ffff:a.b.c.d (mapped) and ::a.b.c.d (compatible) carry an IPv4 address; 64:ff9b::/96 translates one.
        if zeros, (bytes[10] == 0xFF && bytes[11] == 0xFF) || (bytes[10] == 0 && bytes[11] == 0) {
            if bytes[10] == 0, bytes[12 ..< 16].allSatisfy({ $0 == 0 }) || bytes[12 ..< 15].allSatisfy({ $0 == 0 }) {
                return true  // :: and ::1
            }
            return inwardV4(Array(bytes[12 ..< 16]))
        }
        if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B,
            bytes[4 ..< 12].allSatisfy({ $0 == 0 })
        {
            return inwardV4(Array(bytes[12 ..< 16]))
        }
        switch bytes[0] {
            case 0xFC, 0xFD: return true  // unique local
            // link-local fe80::/10, site-local fec0::/10
            case 0xFE: return bytes[1] & 0xC0 == 0x80 || bytes[1] & 0xC0 == 0xC0
            case 0xFF: return true  // multicast
            // documentation
            default: return bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8
        }
    }
}
