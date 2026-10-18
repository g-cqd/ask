import Foundation
import Synchronization
import Testing

@testable import AskAI

/// The Anthropic client end to end over a scripted transport: headers per auth, events out, failures typed.
@Suite("The Anthropic client streams model events and types every failure")
struct AnthropicClientTests {
    private let request = ModelRequest(
        model: "claude-x", maxTokens: 64, systemPrompt: [],
        messages: [ModelMessage(role: .user, blocks: [.text("Hi")])],
        tools: [])

    private func events(_ client: AnthropicClient, auth: AnthropicClient.Auth) async throws -> [ModelEvent] {
        var collected: [ModelEvent] = []
        for try await event in client.stream(request, auth: auth) { collected.append(event) }
        return collected
    }

    private let turn = [
        "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"claude-x\",",
        "\"usage\":{\"input_tokens\":3,\"output_tokens\":1}}}\n\nevent: content_block_start\ndata: {\"type\":\"content_",
        "block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\nevent: content_block_delta\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
        "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
    ]

    @Test func `a subscription request carries the bearer token and the OAuth betas`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: turn)
        let client = AnthropicClient(transport: transport)
        let received = try await events(client, auth: .subscription(accessToken: "sk-ant-oat-T"))
        #expect(
            received == [
                .messageStarted(id: "m", model: "claude-x", usage: TokenUsage(input: 3, output: 1)),
                .blockStarted(index: 0, .text), .textDelta(index: 0, "Hello"), .messageStopped
            ])
        let sent = try #require(transport.sent)
        #expect(sent.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.method == "POST")
        #expect(sent.headers.first { $0.name == "authorization" }?.value == "Bearer sk-ant-oat-T")
        #expect(sent.headers.first { $0.name == "anthropic-beta" }?.value == "claude-code-20250219,oauth-2025-04-20")
        #expect(sent.headers.first { $0.name == "anthropic-version" }?.value == "2023-06-01")
        #expect(!sent.headers.contains { $0.name == "x-api-key" })
        #expect(sent.body == AnthropicRequestEncoder.encode(request))
    }

    @Test func `ANTHROPIC_BASE_URL moves the endpoint, as the official SDK does`() {
        #expect(AnthropicClient.endpoint(environment: [:]).absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(
            AnthropicClient.endpoint(environment: ["ANTHROPIC_BASE_URL": "http://127.0.0.1:8080/"]).absoluteString
                == "http://127.0.0.1:8080/v1/messages")
        #expect(
            AnthropicClient.endpoint(environment: ["ANTHROPIC_BASE_URL": "https://gw.example/anthropic"]).absoluteString
                == "https://gw.example/anthropic/v1/messages")
        #expect(
            AnthropicClient.endpoint(environment: ["ANTHROPIC_BASE_URL": "not a url"]).absoluteString
                == "https://api.anthropic.com/v1/messages")
    }

    @Test func `an API key request uses x-api-key and no OAuth betas`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: turn)
        _ = try await events(AnthropicClient(transport: transport), auth: .apiKey("sk-ant-api-K"))
        let sent = try #require(transport.sent)
        #expect(sent.headers.first { $0.name == "x-api-key" }?.value == "sk-ant-api-K")
        #expect(!sent.headers.contains { $0.name == "authorization" || $0.name == "anthropic-beta" })
    }

    @Test func `an error status becomes a typed failure with the provider's reason`() async {
        let transport = ScriptedTransport(
            status: 429, chunks: [#"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}"#])
        await #expect(
            throws: AnthropicClientError.status(
                429, ProviderFailure(kind: .rateLimited, message: "Slow down"))
        ) {
            _ = try await events(AnthropicClient(transport: transport), auth: .apiKey("k"))
        }
        let opaque = ScriptedTransport(status: 502, chunks: ["<html>bad gateway</html>"])
        await #expect(throws: AnthropicClientError.status(502, nil)) {
            _ = try await events(AnthropicClient(transport: opaque), auth: .apiKey("k"))
        }
    }

    @Test func `a stream that ends mid-event is truncated, not complete`() async {
        let transport = ScriptedTransport(
            status: 200, chunks: [turn[0], turn[1], turn[2], "data: {\"type\":\"content_bl"])
        await #expect(throws: AnthropicClientError.truncated) {
            _ = try await events(AnthropicClient(transport: transport), auth: .apiKey("k"))
        }
    }

    @Test func `an error event mid-stream ends the stream with its failure`() async {
        let transport = ScriptedTransport(
            status: 200,
            chunks: [
                turn[0], turn[1], turn[2],
                "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n"
            ])
        await #expect(
            throws: AnthropicClientError.stream(.provider(ProviderFailure(kind: .overloaded, message: "Overloaded")))
        ) {
            _ = try await events(AnthropicClient(transport: transport), auth: .apiKey("k"))
        }
    }
}
