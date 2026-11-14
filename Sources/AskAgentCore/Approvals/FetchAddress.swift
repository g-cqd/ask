public import Foundation

/// The addresses `fetch` reads (roadmap 0237): `https` only (and `http` to this machine, for local servers), no credentials in them,
/// and never a private, loopback or link-local address unless the host is `localhost` itself. A host's name is its approval's unit.
public enum FetchAddress {
    /// The URL `text` names when `fetch` may read it, nil with the reason otherwise.
    public static func check(_ text: String) -> Result<URL, Refusal> {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(),
            let host = url.host?.lowercased(), !host.isEmpty
        else { return .failure(.notAnAddress) }
        guard url.user == nil, url.password == nil else { return .failure(.credentials) }
        let local = isLocal(host)
        switch scheme {
            case "https": break
            case "http" where local: break
            default: return .failure(.scheme(scheme))
        }
        if !local, isPrivateLiteral(host) { return .failure(.privateAddress(host)) }
        return .success(url)
    }

    /// The host an approval for `text` names, lowercased; nil when `text` is no address.
    public static func host(of text: String) -> String? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    /// Why an address is refused.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notAnAddress
        case credentials
        case scheme(String)
        case privateAddress(String)

        public var description: String {
            switch self {
                case .notAnAddress: "That is not a web address."
                case .credentials: "An address with a user or password in it is not fetched."
                case .scheme(let scheme): "Only https is fetched (http to this machine), not \(scheme)."
                case .privateAddress(let host):
                    "\(host) is a private or local network address; only this machine's localhost is fetched."
            }
        }
    }

    /// Why `host` is refused for what it resolves to, or nil: a name pointing at a private, loopback or link-local address, which the
    /// name alone does not show (security audit 3). This machine by its own name is the person's to read.
    public static func refusal(of host: String, resolvingTo addresses: [String]) -> Refusal? {
        guard !isLocal(host), let inward = addresses.first(where: isPrivateLiteral) else { return nil }
        return .privateAddress("\(host) (it resolves to \(inward))")
    }

    static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// A literal address in a private, loopback, link-local or unspecified range. A name is checked by what it resolves to
    /// (``refusal(of:resolvingTo:)``).
    static func isPrivateLiteral(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = bare.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0 ... 255).contains($0) }) {
            switch (parts[0], parts[1]) {
                case (10, _), (127, _), (0, _), (169, 254), (192, 168): return true
                case (172, let second): return (16 ... 31).contains(second)
                case (100, let second): return (64 ... 127).contains(second)
                default: return false
            }
        }
        let lower = bare.lowercased()
        return lower.contains(":")
            && (lower == "::" || lower == "::1" || lower.hasPrefix("fe80") || lower.hasPrefix("fc")
                || lower.hasPrefix("fd")
                || lower.hasPrefix("::ffff:"))
    }
}
