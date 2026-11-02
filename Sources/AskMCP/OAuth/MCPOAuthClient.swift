internal import AemiJSON
public import AskAI
public import Foundation

/// The steps of a sign-in to a server, once discovery has found its plan (MCP 2025-11-25, Authorization): registering ask as a public
/// client (RFC 7591), the address the person approves in a browser, the code's exchange (with PKCE and the resource indicator), and the
/// refresh.
public struct MCPOAuthClient: Sendable {
    public let plan: MCPOAuthPlan
    let http: any HTTPTransport

    public init(plan: MCPOAuthPlan, http: any HTTPTransport) {
        self.plan = plan
        self.http = http
    }

    /// Registers ask with the authorization server, redirected to `redirectURI`.
    /// - Returns: the client id it was given.
    /// - Throws: ``MCPOAuthError`` when the server takes no registration, or refuses it.
    public func register(redirectURI: String) async throws(MCPOAuthError) -> String {
        guard let endpoint = plan.registrationEndpoint else {
            throw MCPOAuthError("the authorization server takes no registration; set mcp.<server>.oauth.clientId")
        }
        var writer = JSONStreamWriter(options: .rfc8259)
        MCPWire.object(&writer) { body in
            MCPWire.put(&body, "client_name", string: "ask")
            body.key("redirect_uris")
            body.beginArray()
            body.string(redirectURI)
            body.endArray()
            body.key("grant_types")
            body.beginArray()
            body.string("authorization_code")
            body.string("refresh_token")
            body.endArray()
            body.key("response_types")
            body.beginArray()
            body.string("code")
            body.endArray()
            MCPWire.put(&body, "token_endpoint_auth_method", string: "none")
            if let scope = plan.scope { MCPWire.put(&body, "scope", string: scope) }
        }
        let root = try await post(endpoint, body: writer.finish(), type: "application/json", accepting: [200, 201])
        guard let id = root["client_id"].string, !id.isEmpty else {
            throw MCPOAuthError("the registration gave no client id")
        }
        return id
    }

    /// The address the person opens to approve ask.
    public func authorizationURL(clientID: String, redirectURI: String, pkce: PKCE, state: String) -> URL {
        var query: [(String, String)] = [
            ("response_type", "code"), ("client_id", clientID), ("redirect_uri", redirectURI),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"), ("state", state), ("resource", plan.resource)
        ]
        if let scope = plan.scope { query.append(("scope", scope)) }
        let separator = plan.authorizationEndpoint.query == nil ? "?" : "&"
        // %20, not the form encoding's "+": a space in a query is valid that way to every parser.
        return URL(
            string: plan.authorizationEndpoint.absoluteString + separator + FormEncoding.query(query, spaceAs: "%20")
        )!
    }

    /// Exchanges the code the browser brought back for tokens.
    public func exchange(code: String, clientID: String, redirectURI: String, pkce: PKCE, now: Date = Date())
        async throws(MCPOAuthError) -> MCPOAuthTokens
    {
        try await tokens(
            [
                ("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
                ("client_id", clientID),
                ("code_verifier", pkce.verifier), ("resource", plan.resource)
            ],
            keeping: nil,
            now: now
        )
    }

    /// New tokens for `old`, through its refresh token; the old refresh token is kept when the server sends none.
    public func refresh(_ old: MCPOAuthTokens, clientID: String, now: Date = Date()) async throws(MCPOAuthError)
        -> MCPOAuthTokens
    {
        guard let refresh = old.refresh else { throw MCPOAuthError("there is no refresh token: sign in again") }
        return try await tokens(
            [
                ("grant_type", "refresh_token"), ("refresh_token", refresh), ("client_id", clientID),
                ("resource", plan.resource)
            ],
            keeping: refresh,
            now: now
        )
    }

    private func tokens(_ form: [(String, String)], keeping refresh: String?, now: Date) async throws(MCPOAuthError)
        -> MCPOAuthTokens
    {
        let root = try await post(
            plan.tokenEndpoint,
            body: Array(FormEncoding.query(form).utf8),
            type: "application/x-www-form-urlencoded",
            accepting: [200]
        )
        guard let access = root["access_token"].string, !access.isEmpty else {
            throw MCPOAuthError("the token reply had no access token")
        }
        return MCPOAuthTokens(
            access: access,
            refresh: root["refresh_token"].string ?? refresh,
            expires: root["expires_in"].double.map { now.addingTimeInterval($0) }
        )
    }

    /// The JSON object a POST answers with; a refusal says the server's error code, never what was sent.
    private func post(_ url: URL, body: [UInt8], type: String, accepting: Set<Int>) async throws(MCPOAuthError) -> JSON
    {
        let request = HTTPRequest(
            url: url,
            method: "POST",
            headers: [("Content-Type", type), ("Accept", "application/json")],
            body: body,
            allowsRedirects: false
        )
        let reply: HTTPStreamingResponse
        let bytes: [UInt8]
        do {
            reply = try await http.send(request)
            bytes = try await reply.collect(limit: 1 << 20)
        } catch {
            throw MCPOAuthError("the authorization server could not be reached")
        }
        let root = (try? AemiJSON.parse(bytes))?.root
        guard accepting.contains(reply.status), let root, root.isObject else {
            let code = root?["error"].string.map { ": \($0)" } ?? ""
            throw MCPOAuthError("the authorization server refused (HTTP \(reply.status)\(code))")
        }
        return root
    }
}
