internal import Foundation
internal import Testing

@testable import AskAI

/// A request too long for the model's window is told apart from every other refusal, because it is the one the loop
/// can cure, by compacting the conversation and sending it again.
///
/// The bodies are what the servers actually answered (diary 14): llama.cpp and Ollama both refuse before streaming,
/// with HTTP 400, even for a streamed request.
@Suite("A context overflow is recognised, whichever server reports it")
struct ContextOverflowTests {
    private static let openAICompatible: [(server: String, body: String)] = [
        (
            "llama.cpp",
            #"{"error":{"code":400,"message":"request (7100 tokens) exceeds the available context size (2048 tokens), try increasing it","type":"exceed_context_size_error","n_prompt_tokens":7100,"n_ctx":2048}}"#
        ),
        (
            "Ollama",
            #"{"error":{"message":"request (7929 tokens) exceeds the available context size (4096 tokens), try increasing it","type":"invalid_request_error","param":null,"code":null}}"#
        ),
        (
            "OpenAI",
            #"{"error":{"message":"This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens.","type":"invalid_request_error","param":"messages","code":"context_length_exceeded"}}"#
        ),
        (
            "vLLM",
            #"{"object":"error","message":"This model's maximum context length is 32768 tokens. However, you requested 40000 tokens.","type":"BadRequestError","code":400}"#
        )
    ]

    @Test(arguments: ContextOverflowTests.openAICompatible)
    func `an OpenAI-compatible refusal for length is an overflow`(server: String, body: String) {
        let error = OpenAICompatibleError.status(400, OpenAIStreamDecoder.failure(inErrorBody: Array(body.utf8)))
        #expect(error.isContextOverflow, "\(server)")
        #expect(!error.isRetryable, "\(server): sending the same request again cannot succeed")
    }

    @Test func `the window a refusal names is read, so ask can size itself to it`() {
        let windows = ContextOverflowTests.openAICompatible.map { entry in
            OpenAICompatibleError.status(400, OpenAIStreamDecoder.failure(inErrorBody: Array(entry.body.utf8)))
                .reportedContextWindow
        }
        #expect(windows == [2_048, 4_096, 128_000, 32_768])
    }

    @Test func `Anthropic's prompt-too-long refusal is an overflow`() {
        let body =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 210000 tokens > 200000 maximum"}}"#
        #expect(
            AnthropicClientError.status(400, AnthropicStreamDecoder.failure(inErrorBody: Array(body.utf8)))
                .isContextOverflow)
    }

    @Test func `other refusals are not overflows`() {
        let bad =
            #"{"error":{"message":"Unknown parameter: foo","type":"invalid_request_error","code":"unknown_parameter"}}"#
        #expect(
            !OpenAICompatibleError.status(400, OpenAIStreamDecoder.failure(inErrorBody: Array(bad.utf8)))
                .isContextOverflow)
        #expect(!OpenAICompatibleError.status(429, nil).isContextOverflow)
        #expect(!OpenAICompatibleError.truncated.isContextOverflow)
        let anthropic =
            #"{"type":"error","error":{"type":"invalid_request_error","message":"messages: roles must alternate"}}"#
        #expect(
            !AnthropicClientError.status(400, AnthropicStreamDecoder.failure(inErrorBody: Array(anthropic.utf8)))
                .isContextOverflow)
    }

    @Test func `a body with an error object but no type still classifies by its message`() {
        let body = #"{"error":{"message":"the request exceeds the available context size, try increasing it"}}"#
        #expect(
            OpenAICompatibleError.status(400, OpenAIStreamDecoder.failure(inErrorBody: Array(body.utf8)))
                .isContextOverflow)
    }

    @Test func `the window a refusal names is read from each server's wording`() {
        let kind = ProviderFailure.Kind.self
        #expect(kind.contextWindow(describedIn: "exceeds the available context size (2048 tokens), try") == 2048)
        #expect(kind.contextWindow(describedIn: "maximum context length is 32768 tokens. However") == 32768)
        #expect(kind.contextWindow(describedIn: "210000 tokens > 200000 maximum") == 200_000)
        #expect(kind.contextWindow(describedIn: "something else (12 tokens)") == nil)
    }
}
