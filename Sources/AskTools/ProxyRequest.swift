internal import Foundation

/// What the provider proxy does with a request head (roadmap 0021). It serves `CONNECT host:port` tunnels only, to the hosts and ports
/// it allows; a plain HTTP request is refused, since every provider speaks HTTPS, and so is anything it cannot read.
public enum ProxyRequest {
    /// A host and port a tunnel may go to. Host names are kept in lower case without a trailing dot, so one spelling matches another.
    public struct Target: Sendable, Hashable {
        public let host: String
        public let port: Int

        public init(host: String, port: Int) {
            var host = host.lowercased()
            if host.hasSuffix(".") { host.removeLast() }
            self.host = host
            self.port = port
        }

        /// The target of `url`'s host and port, the scheme's default port when none is written; nil when it names no host.
        public init?(url: String) {
            guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty,
                let port = components.port
                    ?? (components.scheme == "https" ? 443 : components.scheme == "http" ? 80 : nil)
            else { return nil }
            self.init(host: host, port: port)
        }
    }

    public enum Decision: Sendable, Equatable {
        /// Open a tunnel to the target.
        case tunnel(Target)
        /// Answer with this status and reason, and close.
        case refuse(Int, String)
    }

    /// What to do with `head`, the request line and headers up to the blank line.
    /// - Parameters:
    ///   - head: the request head, as read.
    ///   - allowed: where tunnels may go.
    ///   - authorization: the `Proxy-Authorization` value a request must carry: only the commands ask gave the proxy's address
    ///     know it, so another program on this machine cannot use the tunnel (security audit 2026-11-22, HIGH-07).
    /// - Returns: a tunnel to an allowed target, or the refusal to send.
    public static func decide(_ head: String, allowing allowed: Set<Target>, authorization: String) -> Decision {
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        let parts = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .refuse(400, "Bad Request") }
        guard parts[0] == "CONNECT" else {
            return .refuse(405, "Method Not Allowed: this proxy only opens HTTPS tunnels to the model providers")
        }
        let presented = lines.dropFirst()
            .compactMap { line -> Substring? in
                guard let colon = line.firstIndex(of: ":"),
                    line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "proxy-authorization"
                else { return nil }
                return line[line.index(after: colon)...]
            }
        guard presented.count == 1, presented[0].trimmingCharacters(in: .whitespaces) == authorization else {
            return .refuse(407, "Proxy Authentication Required")
        }
        guard let target = target(of: parts[1]) else { return .refuse(400, "Bad Request") }
        guard allowed.contains(target) else {
            return .refuse(403, "Forbidden: \(target.host):\(target.port) is not a model provider ask uses")
        }
        return .tunnel(target)
    }

    /// `host:port` or `[v6]:port`, with a port from 1 to 65535.
    private static func target(of authority: Substring) -> Target? {
        guard let colon = authority.lastIndex(of: ":") else { return nil }
        var host = authority[..<colon]
        if host.hasPrefix("["), host.hasSuffix("]") { host = host.dropFirst().dropLast() }
        guard !host.isEmpty, let port = Int(authority[authority.index(after: colon)...]), (1 ... 65_535).contains(port)
        else { return nil }
        return Target(host: String(host), port: port)
    }
}
