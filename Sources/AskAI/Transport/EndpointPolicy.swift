public import Foundation

/// Where a request that carries a credential may be sent (ADR-0024).
///
/// `https` anywhere; plain `http` only to this machine, which is what a local server or gateway needs. A credential
/// sent over plain `http` to another machine travels in the clear to whoever answers. A request with no credential
/// may use plain `http` anywhere: a server on the local network is common and has nothing to leak.
public enum EndpointPolicy {
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Why `url` may not be used, or nil when it may. The reason never repeats the URL, which can carry userinfo.
    public static func refusal(for url: URL, carriesCredential: Bool) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased() else {
            return "it is not a URL"
        }
        switch scheme {
            case "https": return nil
            case "http" where !carriesCredential || loopbackHosts.contains(host): return nil
            case "http":
                return
                    "plain http to another machine would send the credential unencrypted; use https, or http only for localhost"
            default: return "it is not an http or https URL"
        }
    }
}
