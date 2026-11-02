internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskMCP

/// A signed-in server's requests carry its token; a refusal is renewed once and tried again, or kept for the host to ask the person to sign
/// in (MCP 2025-11-25, Authorization; roadmap 0067).
@Suite(
    "An HTTP transport sends the token, renews it once when refused, and keeps the challenge",
    .timeLimit(.minutes(1))
)
struct HTTPMCPAuthorizationTests {
    /// A sign-in whose token is `tokens[n]` after `n` renewals, which renews while `renews` says so.
    final class Tokens: MCPAuthorization {
        private let state: Mutex<(index: Int, refusals: [MCPAuthChallenge?])>
        let tokens: [String]
        let renews: Bool
        init(_ tokens: [String], renews: Bool = true) {
            self.tokens = tokens
            self.renews = renews
            state = Mutex((0, []))
        }
        var refusals: [MCPAuthChallenge?] { state.withLock { $0.refusals } }
        func header() async -> String? { "Bearer " + tokens[state.withLock { $0.index }] }
        func refused(_ challenge: MCPAuthChallenge?) async -> Bool {
            state.withLock { state in
                state.refusals.append(challenge)
                guard renews, state.index + 1 < tokens.count else { return false }
                state.index += 1
                return true
            }
        }
    }

    private static let challenge =
        #"Bearer resource_metadata="https://example.test/.well-known/oauth-protected-resource/mcp""#

    @Test func `every request carries the token`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#) }
        let transport = try HTTPMCPTransport(
            url: HTTPMCP.url,
            userAgent: "t",
            http: http,
            authorization: Tokens(["one"])
        )
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        _ = await HTTPMCP.next(&incoming)
        #expect(http.requests.first?.headers["authorization"] == "Bearer one")
        await transport.close()
    }

    @Test func `a refused token is renewed once and the request sent again`() async throws {
        let http = ScriptedHTTP { seen in
            seen.headers["authorization"] == "Bearer two"
                ? ScriptedHTTP.json(#"{"jsonrpc":"2.0","id":7,"result":{}}"#)
                : ScriptedHTTP.status(401, headers: ["www-authenticate": #"Bearer error="invalid_token""#])
        }
        let tokens = Tokens(["one", "two"])
        let transport = try HTTPMCPTransport(url: HTTPMCP.url, userAgent: "t", http: http, authorization: tokens)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains(#""result""#) == true)
        #expect(tokens.refusals.map { $0?.error } == ["invalid_token"])
        #expect(transport.authorizationChallenge == nil, "answered: nothing for the host")
        await transport.close()
    }

    @Test func `a server that needs sign-in answers the request with that, and its challenge is kept`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.status(401, headers: ["www-authenticate": Self.challenge]) }
        let transport = try HTTPMCP.transport(http)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains("sign in") == true)
        #expect(
            transport.authorizationChallenge?.resourceMetadata?.absoluteString
                == "https://example.test/.well-known/oauth-protected-resource/mcp"
        )
        await transport.close()
    }

    @Test func `a token renewed once and refused again is not tried a third time`() async throws {
        let http = ScriptedHTTP { _ in ScriptedHTTP.status(401, headers: ["www-authenticate": Self.challenge]) }
        let tokens = Tokens(["one", "two", "three"])
        let transport = try HTTPMCPTransport(url: HTTPMCP.url, userAgent: "t", http: http, authorization: tokens)
        var incoming = transport.incoming.makeAsyncIterator()
        try await HTTPMCP.send(HTTPMCP.ping, on: transport)
        #expect(await HTTPMCP.next(&incoming)?.contains("sign in") == true)
        #expect(http.requests.count == 2 && tokens.refusals.count == 1)
        #expect(transport.authorizationChallenge != nil)
        await transport.close()
    }

    @Test func `a token is never sent in the clear to another machine`() {
        #expect(throws: MCPError.self) {
            try HTTPMCPTransport(
                url: URL(string: "http://example.test/mcp")!,
                userAgent: "t",
                http: ScriptedHTTP(),
                authorization: Tokens(["x"])
            )
        }
    }
}
