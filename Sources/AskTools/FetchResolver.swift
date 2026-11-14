internal import Darwin

/// The addresses a host name resolves to, as the system resolves it (security audit 3): `fetch` refuses a name that points at a
/// private, loopback or link-local address, which a name anyone can register may do, and which a number written another way
/// (`2130706433`, `0x7f.1`) does too. A name that does not resolve gives none, and the request then fails by itself.
enum FetchResolver {
    static func addresses(of host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let first = found else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let entry = next {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                entry.pointee.ai_addr,
                entry.pointee.ai_addrlen,
                &name,
                socklen_t(name.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let address = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                // A scope (`fe80::1%en0`) is not part of the address.
                addresses.append(String(address.prefix { $0 != "%" }))
            }
            next = entry.pointee.ai_next
        }
        return addresses
    }
}
