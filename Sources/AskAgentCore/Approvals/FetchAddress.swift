internal import AskAI
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

    /// The host an approval for `text` names, lowercased; nil when `text` is no address. This machine's servers are told apart by
    /// their port (`localhost:3000`): approving one local server is not approving every other (security audit 2026-11-22, CRIT-05).
    public static func host(of text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = url.host?.lowercased()
        else {
            return nil
        }
        guard isLocal(host) else { return host }
        return host + ":" + String(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))
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

    /// A literal address in a range that is not the public internet (``InwardAddress``). A name is checked by what it resolves to
    /// (``refusal(of:resolvingTo:)``).
    static func isPrivateLiteral(_ host: String) -> Bool { InwardAddress.contains(host) }
}
