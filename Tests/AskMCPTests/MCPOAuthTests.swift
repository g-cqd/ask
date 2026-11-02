import AskAI
import Foundation
import Testing

@testable import AskMCP

/// Authorization for a remote MCP server (MCP 2025-11-25, roadmap 0067): the 401's challenge, the protected resource's metadata
/// (RFC 9728), its authorization server's (RFC 8414), dynamic registration (RFC 7591), and the authorization code with PKCE and the
/// resource indicator (RFC 8707), refreshed when it runs out.
@Suite("A server that needs sign-in is authorized as the MCP specification says")
struct MCPOAuthTests {
    private let server = URL(string: "https://mcp.example.com/mcp")!

    @Test func `a Bearer challenge names its metadata, its scope and its error, quoted or not`() {
        let plain = MCPAuthChallenge(
            header:
                #"Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource", scope="read write""#
        )
        #expect(
            plain?.resourceMetadata?.absoluteString == "https://mcp.example.com/.well-known/oauth-protected-resource"
        )
        #expect(plain?.scope == "read write" && plain?.error == nil)
        let step = MCPAuthChallenge(
            header: #"Bearer error="insufficient_scope", scope="a, b", error_description="more""#
        )
        #expect(
            step?.error == "insufficient_scope" && step?.scope == "a, b",
            "a comma inside quotes is part of the value"
        )
        #expect(MCPAuthChallenge(header: "bearer realm=x")?.resourceMetadata == nil, "the scheme is case-insensitive")
        #expect(MCPAuthChallenge(header: #"Basic realm="x""#) == nil)
        #expect(MCPAuthChallenge(header: "") == nil)
    }

    @Test func `without metadata in the challenge, the well-known places are tried, the path's first`() {
        #expect(
            MCPOAuthDiscovery.protectedResourceLocations(for: server, challenge: nil).map(\.absoluteString) == [
                "https://mcp.example.com/.well-known/oauth-protected-resource/mcp",
                "https://mcp.example.com/.well-known/oauth-protected-resource"
            ]
        )
        let named = URL(string: "https://elsewhere.example/prm")!
        #expect(
            MCPOAuthDiscovery.protectedResourceLocations(for: server, challenge: .init(resourceMetadata: named)) == [
                named
            ]
        )
    }

    @Test func `an authorization server's metadata is looked for as RFC 8414 and OpenID Connect say`() {
        #expect(
            MCPOAuthDiscovery.authorizationServerLocations(issuer: URL(string: "https://auth.example.com/tenant1")!)
                .map(\.absoluteString) == [
                    "https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
                    "https://auth.example.com/.well-known/openid-configuration/tenant1",
                    "https://auth.example.com/tenant1/.well-known/openid-configuration"
                ]
        )
        #expect(
            MCPOAuthDiscovery.authorizationServerLocations(issuer: URL(string: "https://auth.example.com")!)
                .map(\.absoluteString) == [
                    "https://auth.example.com/.well-known/oauth-authorization-server",
                    "https://auth.example.com/.well-known/openid-configuration"
                ]
        )
    }

    private static let resourceJSON =
        #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["files"]}"#
    private static let serverJSON =
        #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","registration_endpoint":"https://auth.example.com/register","code_challenge_methods_supported":["S256"]}"#

    private func web(resource: String = resourceJSON, server: String = serverJSON) -> ScriptedHTTP {
        ScriptedHTTP { seen in
            switch seen.url {
                case "https://mcp.example.com/.well-known/oauth-protected-resource/mcp": ScriptedHTTP.json(resource)
                case "https://auth.example.com/.well-known/oauth-authorization-server": ScriptedHTTP.json(server)
                case "https://auth.example.com/register": ScriptedHTTP.json(#"{"client_id":"registered-1"}"#)
                case "https://auth.example.com/token":
                    ScriptedHTTP.json(
                        #"{"access_token":"at-1","token_type":"Bearer","expires_in":3600,"refresh_token":"rt-1"}"#
                    )
                default: ScriptedHTTP.status(404)
            }
        }
    }

    @Test func `discovery finds the endpoints and the scope to ask for`() async throws {
        let plan = try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: web())
        #expect(plan.authorizationEndpoint.absoluteString == "https://auth.example.com/authorize")
        #expect(plan.tokenEndpoint.absoluteString == "https://auth.example.com/token")
        #expect(plan.registrationEndpoint?.absoluteString == "https://auth.example.com/register")
        #expect(plan.scope == "files", "the server's scopes, when the challenge names none")
        #expect(plan.resource == "https://mcp.example.com/mcp")
        let asked = try await MCPOAuthDiscovery.discover(server: server, challenge: .init(scope: "only"), http: web())
        #expect(asked.scope == "only", "the challenge's scope first")
    }

    @Test func `discovery refuses what the specification forbids`() async {
        let noPKCE = Self.serverJSON.replacingOccurrences(
            of: #","code_challenge_methods_supported":["S256"]"#,
            with: ""
        )
        await #expect(throws: MCPOAuthError.self) {
            try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: web(server: noPKCE))
        }
        let other = Self.resourceJSON.replacingOccurrences(
            of: "https://mcp.example.com/mcp",
            with: "https://evil.example/mcp"
        )
        await #expect(throws: MCPOAuthError.self, "metadata for another resource") {
            try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: web(resource: other))
        }
        let plain = Self.serverJSON.replacingOccurrences(
            of: "https://auth.example.com/token",
            with: "http://auth.example.com/token"
        )
        await #expect(throws: MCPOAuthError.self, "a token sent in the clear") {
            try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: web(server: plain))
        }
        let wrongIssuer = Self.serverJSON.replacingOccurrences(
            of: #""issuer":"https://auth.example.com""#,
            with: #""issuer":"https://x.example""#
        )
        await #expect(throws: MCPOAuthError.self, "an issuer that is not the one asked") {
            try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: web(server: wrongIssuer))
        }
    }

    @Test func `registration, the authorization address, the exchange and the refresh carry what they must`()
        async throws
    {
        let http = web()
        let plan = try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: http)
        let redirect = "http://127.0.0.1:53682/callback"
        let client = MCPOAuthClient(plan: plan, http: http)
        let id = try await client.register(redirectURI: redirect)
        #expect(id == "registered-1")
        let registration = try #require(http.requests.first { $0.url.hasSuffix("/register") })
        #expect(registration.body.contains(#""redirect_uris":["http://127.0.0.1:53682/callback"]"#))
        #expect(
            registration.body.contains(#""token_endpoint_auth_method":"none""#)
                && registration.body.contains(#""client_name":"ask""#)
        )
        let pkce = PKCE(verifier: "v-123")
        let address = client.authorizationURL(clientID: id, redirectURI: redirect, pkce: pkce, state: "s-1")
            .absoluteString
        for part in [
            "response_type=code", "client_id=registered-1", "code_challenge=\(pkce.challenge)",
            "code_challenge_method=S256",
            "state=s-1", "scope=files", "resource=https%3A%2F%2Fmcp.example.com%2Fmcp",
            "redirect_uri=http%3A%2F%2F127.0.0.1%3A53682%2Fcallback"
        ] {
            #expect(address.contains(part), "\(part)")
        }
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = try await client.exchange(code: "c-1", clientID: id, redirectURI: redirect, pkce: pkce, now: now)
        #expect(tokens == MCPOAuthTokens(access: "at-1", refresh: "rt-1", expires: now.addingTimeInterval(3600)))
        let exchange = try #require(http.requests.last { $0.url.hasSuffix("/token") })
        for part in [
            "grant_type=authorization_code", "code=c-1", "code_verifier=v-123", "client_id=registered-1",
            "resource=https%3A%2F%2Fmcp.example.com%2Fmcp"
        ] {
            #expect(exchange.body.contains(part), "\(part)")
        }
        _ = try await client.refresh(tokens, clientID: id, now: now)
        let refresh = try #require(http.requests.last { $0.url.hasSuffix("/token") })
        #expect(refresh.body.contains("grant_type=refresh_token") && refresh.body.contains("refresh_token=rt-1"))
        #expect(refresh.body.contains("resource=https%3A%2F%2Fmcp.example.com%2Fmcp"))
    }

    @Test func `a token that is about to run out is due for its refresh`() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(MCPOAuthTokens(access: "a", refresh: "r", expires: now.addingTimeInterval(30)).isDue(at: now))
        #expect(!MCPOAuthTokens(access: "a", refresh: "r", expires: now.addingTimeInterval(3600)).isDue(at: now))
        #expect(
            !MCPOAuthTokens(access: "a", refresh: nil, expires: nil).isDue(at: now),
            "no expiry: used until refused"
        )
    }
}
