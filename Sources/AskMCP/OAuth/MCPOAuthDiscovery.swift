internal import AemiJSON
public import AskAI
public import Foundation

/// Finds how a server is authorized (MCP 2025-11-25, Authorization): its protected resource metadata (RFC 9728), named by its challenge
/// or at the well-known places, then its authorization server's metadata (RFC 8414, else OpenID Connect discovery). What the
/// specification forbids is refused: metadata for another resource, an issuer that is not the one asked, no PKCE with S256, and an
/// endpoint a token would reach in the clear.
public enum MCPOAuthDiscovery {
    /// Where a server's protected resource metadata may be, in the order to try: the challenge's, else the well-known place for the
    /// server's path, then the root's.
    public static func protectedResourceLocations(for server: URL, challenge: MCPAuthChallenge?) -> [URL] {
        if let named = challenge?.resourceMetadata { return [named] }
        let path = trimmedPath(server)
        let base = origin(server) + "/.well-known/oauth-protected-resource"
        return (path.isEmpty ? [base] : [base + path, base]).compactMap(URL.init(string:))
    }

    /// Where an authorization server's metadata may be, in the order RFC 8414 §3.1 and OpenID Connect discovery give.
    public static func authorizationServerLocations(issuer: URL) -> [URL] {
        let path = trimmedPath(issuer)
        let root = origin(issuer)
        let found =
            path.isEmpty
            ? [root + "/.well-known/oauth-authorization-server", root + "/.well-known/openid-configuration"]
            : [
                root + "/.well-known/oauth-authorization-server" + path,
                root + "/.well-known/openid-configuration" + path,
                root + path + "/.well-known/openid-configuration"
            ]
        return found.compactMap(URL.init(string:))
    }

    /// The server's canonical URI (RFC 8707 §2, MCP's resource indicator): its scheme and host in lower case, its port and path, no
    /// fragment, no trailing slash.
    public static func canonical(_ url: URL) -> String { origin(url) + trimmedPath(url) }

    /// What `server` is authorized with, when `challenge` (its 401's) or nothing points to its metadata.
    /// - Throws: ``MCPOAuthError`` when nothing is found, or something the specification forbids.
    public static func discover(server: URL, challenge: MCPAuthChallenge?, http: any HTTPTransport)
        async throws(MCPOAuthError)
        -> MCPOAuthPlan
    {
        let resource = canonical(server)
        var issuer: URL?
        var scopes: [String] = []
        for location in protectedResourceLocations(for: server, challenge: challenge) {
            guard let root = await json(at: location, http: http) else { continue }
            if let named = root["resource"].string, canonical(URL(string: named) ?? server) != resource {
                throw MCPOAuthError("the server's metadata is for another resource")
            }
            root["authorization_servers"]
                .forEachElement { if issuer == nil, let text = $0.string { issuer = URL(string: text) } }
            root["scopes_supported"].forEachElement { if let scope = $0.string { scopes.append(scope) } }
            break
        }
        // A server without that metadata (MCP 2025-03-26) is its own authorization server.
        guard let asked = issuer ?? URL(string: origin(server)) else {
            throw MCPOAuthError("the server's address has no origin to ask")
        }
        let plan = try await authorizationServer(asked, http: http)
        return MCPOAuthPlan(
            issuer: asked,
            authorizationEndpoint: plan.authorize,
            tokenEndpoint: plan.token,
            registrationEndpoint: plan.register,
            scope: challenge?.scope ?? (scopes.isEmpty ? nil : scopes.joined(separator: " ")),
            resource: resource
        )
    }

    private static func authorizationServer(_ issuer: URL, http: any HTTPTransport) async throws(MCPOAuthError)
        -> (authorize: URL, token: URL, register: URL?)
    {
        for location in authorizationServerLocations(issuer: issuer) {
            guard let root = await json(at: location, http: http) else { continue }
            guard let named = root["issuer"].string.flatMap(URL.init(string:)), canonical(named) == canonical(issuer)
            else {
                throw MCPOAuthError("the authorization server's metadata names another issuer")
            }
            var methods: [String] = []
            root["code_challenge_methods_supported"]
                .forEachElement { if let method = $0.string { methods.append(method) } }
            guard methods.contains("S256") else {
                throw MCPOAuthError("the authorization server does not offer PKCE with S256")
            }
            guard let authorize = try endpoint(root["authorization_endpoint"]),
                let token = try endpoint(root["token_endpoint"])
            else {
                throw MCPOAuthError("the authorization server's metadata has no authorization or token endpoint")
            }
            return (authorize, token, try endpoint(root["registration_endpoint"]))
        }
        throw MCPOAuthError("no authorization server metadata was found for \(canonical(issuer))")
    }

    /// An endpoint a token or a code would be sent to: https, or http to this machine only (ADR-0024).
    private static func endpoint(_ value: JSON) throws(MCPOAuthError) -> URL? {
        guard let text = value.string, let url = URL(string: text) else { return nil }
        if let refusal = EndpointPolicy.refusal(for: url, carriesCredential: true) {
            throw MCPOAuthError("an endpoint: \(refusal)")
        }
        return url
    }

    /// The JSON object at `url`, or nil when there is none there.
    static func json(at url: URL, http: any HTTPTransport) async -> JSON? {
        let request = HTTPRequest(
            url: url,
            method: "GET",
            headers: [("Accept", "application/json")],
            body: [],
            allowsRedirects: false
        )
        guard let reply = try? await http.send(request), reply.status == 200,
            let body = try? await reply.collect(limit: 1 << 20),
            let document = try? AemiJSON.parse(body), document.root.isObject
        else { return nil }
        return document.root
    }

    private static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "https"
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        return scheme + "://" + host + port
    }

    private static func trimmedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: true)
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
