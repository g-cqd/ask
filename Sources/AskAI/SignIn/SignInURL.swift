internal import Foundation

/// Which addresses a sign-in may open or send a key to. The server names them, so each is checked (pi-integrations'
/// `browserUrl`, `trustedUrl` and `safeBaseUrl`).
enum SignInURL {
    private static let loopback: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// A link to open in a browser: `https`, no userinfo, which can disguise the real host.
    static func browser(_ text: String?, field: String) throws(SignInError) -> URL {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil,
            url.user() == nil, url.password() == nil
        else { throw .untrustedURL(field) }
        return url
    }

    /// A link under `base`: the same origin, and the same path or below it, with no encoded dot or slash that could
    /// climb out of it.
    static func trusted(_ text: String?, under base: URL, field: String) throws(SignInError) -> URL {
        let url = try browser(text, field: field)
        let path = url.path(percentEncoded: true)
        let prefix = base.path(percentEncoded: true).trimmingSuffix("/")
        let escapes = ["%2e", "%2f", "%5c"].contains { path.lowercased().contains($0) }
        guard url.host()?.lowercased() == base.host()?.lowercased(), (url.port ?? 443) == (base.port ?? 443), !escapes,
            prefix.isEmpty || path == prefix || path.hasPrefix(prefix + "/")
        else { throw .untrustedURL(field) }
        return url
    }

    /// A configured API base: `https`, or `http` to this machine; no userinfo, query or fragment. Without trailing
    /// slashes.
    static func base(_ text: String, field: String) throws(SignInError) -> URL {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(),
            url.user() == nil, url.password() == nil, url.query() == nil, url.fragment() == nil,
            scheme == "https" || (scheme == "http" && loopback.contains(host))
        else { throw .untrustedURL(field) }
        return url
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: Character) -> String {
        var text = self
        while text.last == suffix { text.removeLast() }
        return text
    }
}
