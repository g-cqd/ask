internal import Foundation
internal import Testing

@testable import AskAI

/// A server that cannot verify the reasoning ask sent back refuses the whole request. The run must go on without it, once,
/// say so, and stop sending it (ADR-0062). Probed on the live backend: HTTP 400, type invalid_request_error, code
/// invalid_encrypted_content, for altered, truncated and invented sealed content alike.
struct ResponsesReplayFallbackTests {
    private static let refusal =
        #"{"error":{"message":"The encrypted content for item rs_1 could not be verified. Reason: Encrypted content could not be decrypted or parsed.","type":"invalid_request_error","param":"input","code":"invalid_encrypted_content"}}"#
    private static let otherRefusal =
        #"{"error":{"message":"Unsupported value.","type":"invalid_request_error","param":"reasoning.effort","code":"unsupported_value"}}"#
    private static let dialect = ResponsesDialect(sendsOutputLimit: false, replaysReasoning: true)

    private static func answer() throws -> String {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Responses/llamacpp-text.sse")
        return String(decoding: try Data(contentsOf: fixture), as: UTF8.self)
    }

    private static func request(replaying: Bool = true) throws -> ModelRequest {
        let signature = ReasoningProvenance.mark(
            scheme: "responses",
            payload: ResponsesStreamDecoder.reasoningPayload(id: "rs_1", summaries: [], sealed: "SEALED"))
        let call = RequestBlock.toolCall(
            id: "c1", name: "read", input: try JSONObject(validating: Array(#"{"path":"x"}"#.utf8)))
        let assistant: [RequestBlock] = replaying ? [.thinking(text: "", signature: signature), call] : [call]
        return ModelRequest(
            model: "m", maxTokens: 10, systemPrompt: [],
            messages: [
                ModelMessage(role: .user, blocks: [.text("go")]), ModelMessage(role: .assistant, blocks: assistant),
                ModelMessage(role: .user, blocks: [.toolResult(id: "c1", content: "data", isError: false)])
            ], tools: [])
    }

    private func run(
        _ replies: [SequencedTransport.Reply], request: ModelRequest, gate: ReasoningReplayGate? = ReasoningReplayGate()
    ) async -> (transport: SequencedTransport, events: [ModelEvent], failure: (any Error)?) {
        let transport = SequencedTransport(replies)
        let client = ResponsesClient(
            transport: transport, baseURL: URL(string: "https://example.test/v1")!, dialect: Self.dialect, replay: gate)
        var events: [ModelEvent] = []
        do { for try await event in client.stream(request) { events.append(event) } } catch {
            return (transport, events, error)
        }
        return (transport, events, nil)
    }

    private func bodies(_ transport: SequencedTransport) -> [String] { transport.sent.map(\.bodyText) }

    @Test func `a refusal of the replayed reasoning is retried once without it, and the run goes on`() async throws {
        let result = await run([.json(400, Self.refusal), .json(200, try Self.answer())], request: try Self.request())
        #expect(result.failure == nil)
        let sent = bodies(result.transport)
        try #require(sent.count == 2)
        #expect(sent[0].contains(#""type":"reasoning""#) && sent[0].contains("SEALED"))
        #expect(!sent[1].contains(#""type":"reasoning""#) && !sent[1].contains("SEALED"))
        #expect(sent[1].contains(#""type":"function_call""#), "only the reasoning is dropped, not the history")
        #expect(result.events.contains { if case .textDelta = $0 { true } else { false } })
    }

    @Test func `the person is told, before the answer, that the reasoning was dropped`() async throws {
        let result = await run([.json(400, Self.refusal), .json(200, try Self.answer())], request: try Self.request())
        let notice = try #require(result.events.firstIndex { if case .notice = $0 { true } else { false } })
        let text = try #require(result.events.firstIndex { if case .textDelta = $0 { true } else { false } })
        #expect(notice < text)
        guard case .notice(let words) = result.events[notice] else { return }
        #expect(words.contains("reasoning") && !words.contains("SEALED") && !words.contains("rs_1"))
    }

    @Test func `after a refusal the gate is closed and later requests send no reasoning and make one request`()
        async throws
    {
        let gate = ReasoningReplayGate()
        _ = await run(
            [.json(400, Self.refusal), .json(200, try Self.answer())], request: try Self.request(), gate: gate)
        #expect(!gate.isOpen)
        let later = await run([.json(200, try Self.answer())], request: try Self.request(), gate: gate)
        #expect(later.failure == nil)
        #expect(later.transport.sent.count == 1)
        #expect(!bodies(later.transport)[0].contains("SEALED"))
        #expect(!later.events.contains { if case .notice = $0 { true } else { false } }, "said once, not every step")
    }

    @Test func `without a gate each request may retry, and nothing is remembered`() async throws {
        let result = await run(
            [.json(400, Self.refusal), .json(200, try Self.answer())], request: try Self.request(), gate: nil)
        #expect(result.failure == nil && result.transport.sent.count == 2)
    }

    @Test func `any other refusal is not retried and is not taken for a reasoning problem`() async throws {
        let gate = ReasoningReplayGate()
        let result = await run(
            [.json(400, Self.otherRefusal), .json(200, try Self.answer())], request: try Self.request(), gate: gate)
        #expect(result.failure != nil)
        #expect(result.transport.sent.count == 1)
        #expect(gate.isOpen)
    }

    @Test func `a second refusal ends the run with the server's reason after exactly two requests`() async throws {
        let result = await run([.json(400, Self.refusal), .json(400, Self.refusal)], request: try Self.request())
        #expect(result.failure != nil)
        #expect(result.transport.sent.count == 2)
    }

    @Test func `a request that carries no reasoning is never retried for this refusal`() async throws {
        let gate = ReasoningReplayGate()
        let result = await run(
            [.json(400, Self.refusal), .json(200, try Self.answer())], request: try Self.request(replaying: false),
            gate: gate)
        #expect(result.failure != nil)
        #expect(result.transport.sent.count == 1)
        #expect(gate.isOpen)
    }

    @Test func `the failure kind is decoded from the server's code, not from its wording`() throws {
        let reworded =
            #"{"error":{"message":"Something else entirely.","type":"invalid_request_error","param":"input","code":"invalid_encrypted_content"}}"#
        let kind = OpenAIStreamDecoder.failure(inErrorBody: Array(reworded.utf8))?.kind
        #expect(kind == .rejectedReasoning)
        let ordinary = OpenAIStreamDecoder.failure(inErrorBody: Array(Self.otherRefusal.utf8))?.kind
        #expect(ordinary == .invalidRequest)
    }

    @Test func `the Codex client replays the current loop's reasoning, and the ordinary dialect does not`() async throws
    {
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", expiresAt: 9, accountID: "acct")
        let codex = ScriptedTransport(status: 200, chunks: [try Self.answer()])
        for try await _ in ResponsesClient.codex(transport: codex, credentials: credentials, session: "s")
            .stream(try Self.request())
        {}
        #expect(try #require(codex.sent).bodyText.contains("SEALED"))
        let plain = ScriptedTransport(status: 200, chunks: [try Self.answer()])
        let client = ResponsesClient(transport: plain, baseURL: URL(string: "https://example.test/v1")!)
        for try await _ in client.stream(try Self.request()) {}
        #expect(!(try #require(plain.sent).bodyText.contains("SEALED")))
    }

    @Test func `a refusal that arrives after events were delivered is not retried, so nothing is shown twice`()
        async throws
    {
        // Two reads: the first delivers the response's start, the second carries the refusal. In one read the start would
        // die with the failed batch and nothing would have been shown.
        let started =
            "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r\",\"model\":\"m\"}}\n\n"
        let refused =
            "event: error\ndata: {\"type\":\"error\",\"code\":\"invalid_encrypted_content\",\"message\":\"late\"}\n\n"
        let transport = ScriptedTransport(status: 200, chunks: [started, refused])
        let gate = ReasoningReplayGate()
        let client = ResponsesClient(
            transport: transport, baseURL: URL(string: "https://example.test/v1")!, dialect: Self.dialect, replay: gate)
        var events: [ModelEvent] = []
        var failure: (any Error)?
        do { for try await event in client.stream(try Self.request()) { events.append(event) } } catch {
            failure = error
        }
        #expect(failure != nil)
        #expect(
            events.contains { if case .messageStarted = $0 { true } else { false } }, "the start was delivered first")
        #expect(gate.isOpen)
        #expect(!events.contains { if case .notice = $0 { true } else { false } })
    }

    @Test func `a refusal sent as the first event of a successful stream is retried the same way`() async throws {
        let first =
            "event: error\ndata: {\"type\":\"error\",\"code\":\"invalid_encrypted_content\",\"message\":\"early\"}\n\n"
        let gate = ReasoningReplayGate()
        let result = await run(
            [.json(200, first), .json(200, try Self.answer())], request: try Self.request(), gate: gate)
        #expect(result.failure == nil && result.transport.sent.count == 2)
        #expect(!gate.isOpen)
        #expect(!bodies(result.transport)[1].contains("SEALED"))
    }
}
