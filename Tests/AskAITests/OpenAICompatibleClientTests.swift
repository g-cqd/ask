internal import Foundation
internal import Testing

@testable import AskAI

/// The client sends to `/chat/completions`, authenticates only when configured to, and turns every failure into an
/// error the loop knows whether to retry.
@Suite("The OpenAI-compatible client streams, authenticates and fails usefully")
struct OpenAICompatibleClientTests {
    private static let base = URL(string: "http://127.0.0.1:8181/v1")!
    private static let request = ModelRequest(
        model: "m", maxTokens: 10, systemPrompt: [], messages: [ModelMessage(role: .user, blocks: [.text("x")])],
        tools: [])

    private static let recorded: [String] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/OpenAICompatible/llamacpp-text.sse")
        // Delivered in 50-byte chunks, as a network would, splitting events and characters alike.
        let bytes = Array((try? Data(contentsOf: url)) ?? Data())
        return stride(from: 0, to: bytes.count, by: 50)
            .map {
                String(decoding: bytes[$0 ..< Swift.min(bytes.count, $0 + 50)], as: UTF8.self)
            }
    }()

    private func collect(_ client: OpenAICompatibleClient) async throws -> [ModelEvent] {
        var events: [ModelEvent] = []
        for try await event in client.stream(Self.request) { events.append(event) }
        return events
    }

    @Test func `a recorded stream arrives as a complete response`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: Self.recorded)
        var assembler = ResponseAssembler()
        for event in try await collect(OpenAICompatibleClient(transport: transport, baseURL: Self.base)) {
            try assembler.apply(event)
        }
        let response = try assembler.finish()
        #expect(response.stopReason == .endTurn)
        #expect(transport.sent?.url.absoluteString == "http://127.0.0.1:8181/v1/chat/completions")
    }

    @Test func `the key is sent as a bearer token, and nothing when there is none`() async throws {
        let keyed = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(OpenAICompatibleClient(transport: keyed, baseURL: Self.base, apiKey: "sk-1"))
        #expect(keyed.sent?.headers.contains { $0.name == "authorization" && $0.value == "Bearer sk-1" } == true)
        let open = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(OpenAICompatibleClient(transport: open, baseURL: Self.base))
        #expect(open.sent?.headers.contains { $0.name == "authorization" } == false)
    }

    @Test func `extra headers a gateway asks for are sent`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(OpenAICompatibleClient(transport: transport, baseURL: Self.base, headers: ["x-org": "o"]))
        #expect(transport.sent?.headers.contains { $0.name == "x-org" && $0.value == "o" } == true)
    }

    @Test func `a status error carries the server's reason and retry advice`() async {
        let body = #"{"error":{"message":"slow down","type":"rate_limit_exceeded","code":429}}"#
        let transport = ScriptedTransport(status: 429, chunks: [body], headers: ["retry-after": "2"])
        do {
            _ = try await collect(OpenAICompatibleClient(transport: transport, baseURL: Self.base))
            Issue.record("a 429 did not throw")
        } catch let error as OpenAICompatibleError {
            #expect(error == .status(429, ProviderFailure(kind: .rateLimited, message: "slow down"), retryAfter: 2))
            #expect(error.isRetryable)
            #expect(error.retryAfter == .seconds(2))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func `a refused request is not retried`() {
        let error = OpenAICompatibleError.status(400, ProviderFailure(kind: .invalidRequest, message: "bad"))
        #expect(!error.isRetryable)
    }

    @Test func `a stream cut off before it says why it stopped is retryable`() async {
        let cut = [
            #"data: {"id":"r","model":"m","choices":[{"delta":{"content":"par"},"finish_reason":null}]}"# + "\n\n"
        ]
        do {
            _ = try await collect(
                OpenAICompatibleClient(transport: ScriptedTransport(status: 200, chunks: cut), baseURL: Self.base))
            Issue.record("an unfinished stream did not throw")
        } catch let error as OpenAICompatibleError {
            #expect(error == .stream(.unfinished))
            #expect(error.isRetryable)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
