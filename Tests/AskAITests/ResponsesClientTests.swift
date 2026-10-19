internal import Foundation
internal import Testing

@testable import AskAI

/// The client sends to `/responses`, authenticates only when configured to, and turns every failure into an error the
/// loop knows whether to retry, as the chat-completions client does.
@Suite("The Responses client streams, authenticates and fails usefully")
struct ResponsesClientTests {
    private static let base = URL(string: "http://127.0.0.1:8190/v1")!
    private static let request = ModelRequest(
        model: "m", maxTokens: 10, systemPrompt: [], messages: [ModelMessage(role: .user, blocks: [.text("x")])],
        tools: [])

    private static let recorded: [String] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Responses/llamacpp-text.sse")
        let bytes = Array((try? Data(contentsOf: url)) ?? Data())
        return stride(from: 0, to: bytes.count, by: 50)
            .map { String(decoding: bytes[$0 ..< Swift.min(bytes.count, $0 + 50)], as: UTF8.self) }
    }()

    private func collect(_ client: ResponsesClient) async throws -> [ModelEvent] {
        var events: [ModelEvent] = []
        for try await event in client.stream(Self.request) { events.append(event) }
        return events
    }

    @Test func `a recorded stream arrives as a complete response, from /responses`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: Self.recorded)
        var assembler = ResponseAssembler()
        for event in try await collect(ResponsesClient(transport: transport, baseURL: Self.base)) {
            try assembler.apply(event)
        }
        #expect(try assembler.finish().stopReason == .endTurn)
        #expect(transport.sent?.url.absoluteString == "http://127.0.0.1:8190/v1/responses")
        #expect(transport.sent?.method == "POST")
    }

    @Test func `the key is a bearer token, absent when there is none, and extra headers go too`() async throws {
        let keyed = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(
            ResponsesClient(transport: keyed, baseURL: Self.base, apiKey: "sk-1", headers: ["x-a": "b"]))
        #expect(keyed.sent?.headers.contains { $0.name == "authorization" && $0.value == "Bearer sk-1" } == true)
        #expect(keyed.sent?.headers.contains { $0.name == "x-a" && $0.value == "b" } == true)
        let open = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(ResponsesClient(transport: open, baseURL: Self.base))
        #expect(open.sent?.headers.contains { $0.name == "authorization" } == false)
    }

    @Test func `the output limit is sent unless the client is told the server refuses one`() async throws {
        let sends = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(ResponsesClient(transport: sends, baseURL: Self.base))
        #expect(sends.sent?.bodyText.contains(#""max_output_tokens":10"#) == true)
        let omits = ScriptedTransport(status: 200, chunks: Self.recorded)
        _ = try await collect(
            ResponsesClient(transport: omits, baseURL: Self.base, dialect: ResponsesDialect(sendsOutputLimit: false)))
        #expect(omits.sent?.bodyText.contains("max_output_tokens") == false)
    }

    @Test func `a refusal for length is recognised, with the window the server names`() async {
        let body =
            #"{"error":{"code":400,"message":"request (40010 tokens) exceeds the available context size (8192 tokens), try increasing it","type":"exceed_context_size_error","n_prompt_tokens":40010,"n_ctx":8192}}"#
        let transport = ScriptedTransport(status: 400, chunks: [body])
        do {
            _ = try await collect(ResponsesClient(transport: transport, baseURL: Self.base))
            Issue.record("a refusal streamed")
        } catch let error as any RetryAdvice {
            #expect(error.isContextOverflow)
            #expect(error.reportedContextWindow == 8192)
        } catch { Issue.record("\(error)") }
    }

    @Test func `a stream cut before a terminal event is a retryable failure, not a short answer`() async {
        let transport = ScriptedTransport(
            status: 200,
            chunks: [
                "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r\"}}\n\n"
            ])
        do {
            _ = try await collect(ResponsesClient(transport: transport, baseURL: Self.base))
            Issue.record("a cut stream completed")
        } catch let error as any RetryAdvice { #expect(error.isRetryable) } catch { Issue.record("\(error)") }
    }
}
