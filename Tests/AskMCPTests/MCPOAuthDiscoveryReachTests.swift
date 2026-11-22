internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// What a server names during discovery is asked only if it may be (security audit 2026-11-22, CRIT-05): a challenge or metadata
/// naming an address on this machine or the local network, or plain http, is not fetched for a server on the internet.
@Suite("Discovery asks only what it may")
struct MCPOAuthDiscoveryReachTests {
    private let server = URL(string: "https://mcp.example.com/mcp")!

    private static let serverJSON =
        #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#

    private func web(issuer: String) -> ScriptedHTTP {
        ScriptedHTTP { seen in
            switch seen.url {
                case "https://mcp.example.com/.well-known/oauth-protected-resource/mcp":
                    ScriptedHTTP.json(
                        #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["\#(issuer)"]}"#
                    )
                case "https://auth.example.com/.well-known/oauth-authorization-server":
                    ScriptedHTTP.json(Self.serverJSON)
                default:
                    ScriptedHTTP.json(
                        Self.serverJSON.replacingOccurrences(of: "https://auth.example.com", with: issuer)
                    )
            }
        }
    }

    @Test func `a challenge naming an inward or plain address is not fetched; the well-known place is asked instead`()
        async throws
    {
        for named in [
            "http://169.254.169.254/latest/meta-data", "https://[0:0:0:0:0:ffff:169.254.169.254]/x",
            "https://127.0.0.1:9200/",
            "https://localhost/x", "http://metadata.example.com/x"
        ] {
            let http = web(issuer: "https://auth.example.com")
            let plan = try await MCPOAuthDiscovery.discover(
                server: server,
                challenge: MCPAuthChallenge(resourceMetadata: URL(string: named)!),
                http: http
            )
            #expect(!http.requests.contains { $0.url == named }, "\(named) was fetched")
            #expect(plan.tokenEndpoint.absoluteString == "https://auth.example.com/token")
        }
    }

    @Test func `an authorization server on an inward address is refused, not asked`() async {
        for issuer in ["https://169.254.169.254", "https://[fe81::1]", "https://10.0.0.5", "http://auth.example.com"] {
            let http = web(issuer: issuer)
            await #expect(throws: MCPOAuthError.self, "\(issuer)") {
                try await MCPOAuthDiscovery.discover(server: server, challenge: nil, http: http)
            }
            #expect(!http.requests.contains { $0.url.hasPrefix(issuer) }, "\(issuer) was asked")
        }
    }

    @Test func `a server on this machine may name this machine`() {
        let local = URL(string: "http://localhost:8080/mcp")!
        #expect(MCPOAuthDiscovery.mayAsk(URL(string: "http://localhost:8081/.well-known/x")!, for: local))
        #expect(!MCPOAuthDiscovery.mayAsk(URL(string: "http://localhost:8081/x")!, for: server))
        #expect(MCPOAuthDiscovery.mayAsk(URL(string: "https://auth.example.com/x")!, for: local))
    }
}
