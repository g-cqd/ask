internal import Foundation
internal import Testing

@testable import AskAI

/// What ask sends to the ChatGPT Codex backend: its address, the headers that identify the account and the session, and a
/// body of the shape that backend accepts. Taken from pi's Codex streamer, the working implementation to hand; it has not
/// been observed against the live service, so a first real run is the test of the rest (roadmap 0036).
@Suite("The Codex client addresses the ChatGPT backend the way its CLI does")
struct CodexClientTests {
    private static let credentials = CodexCredentials(
        accessToken: "at-1", refreshToken: "rt-1", expiresAt: 9, accountID: "acct_42")
    private static let request = ModelRequest(
        model: "gpt-x", maxTokens: 777, systemPrompt: ["Be brief."],
        messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])

    private func send(_ credentials: CodexCredentials = credentials, session: String = "sess-1") async throws
        -> HTTPRequest
    {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Responses/llamacpp-text.sse")
        let transport = ScriptedTransport(
            status: 200, chunks: [String(decoding: try Data(contentsOf: fixture), as: UTF8.self)])
        let client = ResponsesClient.codex(transport: transport, credentials: credentials, session: session)
        for try await _ in client.stream(Self.request) {}
        return try #require(transport.sent)
    }

    @Test func `requests go to the Codex responses address`() async throws {
        let sent = try await send()
        #expect(sent.url.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
        #expect(sent.method == "POST")
    }

    @Test func `the headers name the account, the client and the session, and carry the token`() async throws {
        let headers = Dictionary(
            uniqueKeysWithValues: try await send().headers.map { ($0.name.lowercased(), $0.value) })
        #expect(headers["authorization"] == "Bearer at-1")
        #expect(headers["chatgpt-account-id"] == "acct_42")
        #expect(headers["originator"] == "ask")
        #expect(headers["openai-beta"] == "responses=experimental")
        #expect(headers["session-id"] == "sess-1")
        #expect(headers["x-client-request-id"] == "sess-1")
        #expect(headers["accept"] == "text/event-stream")
    }

    @Test func `the body has no output limit, never stores, and keys the prompt cache by the session`() async throws {
        let body = try await send().bodyText
        #expect(!body.contains("max_output_tokens"))
        #expect(body.contains(#""store":false"#))
        #expect(body.contains(#""prompt_cache_key":"sess-1""#))
        #expect(body.contains(#""instructions":"Be brief.""#))
    }

    @Test func `the access token is never in the body`() async throws {
        let body = try await send().bodyText
        #expect(!body.contains("at-1"))
        #expect(!body.contains("rt-1"))
    }
}
