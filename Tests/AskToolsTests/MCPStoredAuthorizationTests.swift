import AskAI
import AskMCP
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// A kept sign-in's header, renewed through its stored token endpoint before it runs out or when refused (roadmap 0067).
@Suite("A stored sign-in sends its token, and renews it when due or refused")
struct MCPStoredAuthorizationTests {
    /// The token endpoint, answering every refresh with `fresh-n`.
    final class TokenEndpoint: HTTPTransport {
        let bodies = Mutex<[String]>([])
        func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
            let count = bodies.withLock { bodies in
                bodies.append(String(decoding: request.body, as: UTF8.self))
                return bodies.count
            }
            let reply = #"{"access_token":"fresh-\#(count)","expires_in":3600}"#
            let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
            continuation.yield(Array(reply.utf8))
            continuation.finish()
            return HTTPStreamingResponse(status: 200, headers: ["content-type": "application/json"], body: body)
        }
    }

    private static let server = "https://mcp.example.com/mcp"

    private func file(expiresAt: Double?, refresh: String = "rt-1") throws -> CredentialFile {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = CredentialFile(url: root.appending(path: "credentials.json"))
        try file.saveMCP(
            MCPServerCredentials(
                server: Self.server,
                issuer: "https://auth.example.com",
                tokenEndpoint: "https://auth.example.com/token",
                clientID: "c-1",
                redirectURI: "http://127.0.0.1:1/callback",
                accessToken: "at-1",
                refreshToken: refresh,
                expiresAt: expiresAt
            )
        )
        return file
    }

    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func `a token not yet due is sent as it is, and none is sent without a sign-in`() async throws {
        let http = TokenEndpoint()
        let stored = MCPStoredAuthorization(server: Self.server, file: try file(expiresAt: 20_000), http: http) {
            self.now
        }
        #expect(await stored.header() == "Bearer at-1")
        #expect(http.bodies.withLock { $0 }.isEmpty)
        let other = MCPStoredAuthorization(
            server: "https://else.example/mcp",
            file: try file(expiresAt: nil),
            http: http
        )
        #expect(await other.header() == nil)
    }

    @Test func `a token about to run out is renewed first, saved, and the old refresh token kept`() async throws {
        let http = TokenEndpoint()
        let file = try file(expiresAt: 10_030)
        let stored = MCPStoredAuthorization(server: Self.server, file: file, http: http) { self.now }
        #expect(await stored.header() == "Bearer fresh-1")
        let saved = try #require(try file.loadMCP(server: Self.server))
        #expect(saved.accessToken == "fresh-1" && saved.refreshToken == "rt-1" && saved.expiresAt == 13_600)
        let body = try #require(http.bodies.withLock { $0 }.first)
        #expect(body.contains("grant_type=refresh_token") && body.contains("client_id=c-1"))
    }

    @Test func `a refused token is renewed; one asked for more scope, or without a refresh token, is not`() async throws
    {
        let http = TokenEndpoint()
        let stored = MCPStoredAuthorization(server: Self.server, file: try file(expiresAt: nil), http: http) {
            self.now
        }
        #expect(await stored.refused(MCPAuthChallenge(error: "invalid_token")))
        #expect(await stored.header() == "Bearer fresh-1")
        #expect(!(await stored.refused(MCPAuthChallenge(error: "insufficient_scope"))), "more scope needs the person")
        let bare = MCPStoredAuthorization(server: Self.server, file: try file(expiresAt: nil, refresh: ""), http: http)
        #expect(!(await bare.refused(nil)))
    }
}
