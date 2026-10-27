internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// Sending a request to Cloud Code and reading what comes back, against the recorded streams.
struct AgyClientTests {
    private static let session = AgySession(accessToken: "at-1", projectID: "proj-1")
    private static let request = ModelRequest(
        model: "claude-sonnet-5-5-low", maxTokens: 500, systemPrompt: ["s"],
        messages: [ModelMessage(role: .user, blocks: [.text("hi")])], tools: [])

    private static func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Agy/\(name).sse")
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private static func events(
        _ transport: SequencedTransport, _ request: ModelRequest = request
    ) async throws -> [ModelEvent] {
        var events: [ModelEvent] = []
        for try await event in AgyClient(transport: transport, newID: { "id-1" }).stream(request, session: session) {
            events.append(event)
        }
        return events
    }

    @Test func `the request goes to the one probed address, with a token and ask's own identity, once each`()
        async throws
    {
        let transport = SequencedTransport([.json(200, try Self.fixture("stream-claude-call"))])
        _ = try await Self.events(transport)
        let sent = try #require(transport.sent.first)
        #expect(sent.method == "POST")
        #expect(
            sent.url.absoluteString
                == "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse")
        func values(_ name: String) -> [String] { sent.headers.filter { $0.name == name }.map(\.value) }
        #expect(values("authorization") == ["Bearer at-1"])
        #expect(values("user-agent") == ["antigravity/cli/1.4.0 ask/0 (Antigravity subscription connector)"])
        #expect(values("accept") == ["text/event-stream"] && values("content-type") == ["application/json"])
    }

    @Test func `the body is the encoder's, under the session's project`() async throws {
        let transport = SequencedTransport([.json(200, try Self.fixture("stream-claude-call"))])
        _ = try await Self.events(transport)
        let body = try AemiJSON.parse(try #require(transport.sent.first).body).root
        #expect(body["project"].string == "proj-1" && body["model"].string == "claude-sonnet-5-5-low")
        #expect(body["requestId"].string == "ask-id-1" && body["userPromptId"].string == "id-1")
        #expect(body["request"]["contents"].array?.first?["parts"].array?.first?["text"].string == "hi")
    }

    @Test func `two requests do not share ids`() async throws {
        let transport = SequencedTransport([.json(200, try Self.fixture("stream-claude-call"))])
        let client = AgyClient(transport: transport)
        for _ in 0 ..< 2 { for try await _ in client.stream(Self.request, session: Self.session) {} }
        let ids = try transport.sent.map { try AemiJSON.parse($0.body).root["requestId"].string }
        #expect(ids.count == 2 && ids[0] != ids[1] && ids.allSatisfy { $0?.hasPrefix("ask-") == true })
    }

    @Test func `the events are the decoder's, whole`() async throws {
        let text = try Self.fixture("stream-claude-call")
        var decoder = AgyStreamDecoder()
        var framer = SSEDecoder()
        var frames: [SSEEvent] = []
        var expected: [ModelEvent] = []
        try framer.feed(Array(text.utf8).span, into: &frames)
        for frame in frames { try decoder.decode(frame, into: &expected) }
        try decoder.finish(into: &expected)
        #expect(try await Self.events(SequencedTransport([.json(200, text)])) == expected)
        #expect(expected.last == .messageStopped && expected.count > 4)
    }

    @Test func `a refusal is a status error with the server's reason`() async throws {
        let body =
            #"{"error":{"code":503,"message":"No capacity available for model m on the server","status":"UNAVAILABLE"}}"#
        do { _ = try await Self.events(SequencedTransport([.json(503, body)])) } catch let error
            as ProviderStreamError<OpenAIStreamError>
        {
            guard case .status(503, let failure?, _) = error else {
                Issue.record("not a 503 with a reason: \(error)")
                return
            }
            #expect(failure.kind == .overloaded && failure.message.hasPrefix("No capacity"))
            return
        }
        Issue.record("a 503 was not an error")
    }

    @Test func `a refused token is an authentication failure`() async throws {
        do {
            _ = try await Self.events(SequencedTransport([.json(401, #"{"error":{"code":401,"message":"bad"}}"#)]))
        } catch let error
            as ProviderStreamError<OpenAIStreamError>
        {
            guard case .status(401, let failure?, _) = error else {
                Issue.record("not a 401: \(error)")
                return
            }
            #expect(failure.kind == .authentication)
            return
        }
        Issue.record("a 401 was not an error")
    }

    @Test func `a stream that stops before its finish reason is reported unfinished`() async throws {
        let cut =
            #"data: {"response":{"candidates":[{"content":{"parts":[{"text":"x"}]}}],"modelVersion":"m","responseId":"r"}}"#
            + "\r\n\r\n"
        do { _ = try await Self.events(SequencedTransport([.json(200, cut)])) } catch let error
            as ProviderStreamError<OpenAIStreamError>
        {
            #expect(error == .stream(.unfinished) && error.isRetryable)
            return
        }
        Issue.record("a cut stream was not an error")
    }

    @Test func `an explicit thinking control fails before anything is sent`() async throws {
        let transport = SequencedTransport([.json(200, try Self.fixture("stream-claude-call"))])
        var asked = Self.request
        asked.thinking = .effort(.high)
        await #expect(throws: ThinkingError.unsupportedProtocol("Antigravity")) {
            _ = try await Self.events(transport, asked)
        }
        #expect(transport.sent.isEmpty)
    }
}
