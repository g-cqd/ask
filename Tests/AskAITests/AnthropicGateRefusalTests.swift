import Testing

@testable import AskAI

/// The Claude subscription's other refusals, in words (roadmap 0165, ADR-0007). The gate answers a prompt shape it rejects with a 429
/// that reads as a rate limit; when the subscription's own headers say every quota still allows requests, the person is told that it may
/// be the request's shape and given the request id, without giving up the retry a genuine burst limit needs.
@Suite("A refusal from the subscription gate says what it may be")
struct AnthropicGateRefusalTests {
    static let rateLimited = Array(#"{"type":"error","error":{"type":"rate_limit_error","message":"Error"}}"#.utf8)
    static let allowed = [
        "anthropic-ratelimit-unified-status": "allowed", "anthropic-ratelimit-unified-5h-status": "allowed",
        "anthropic-ratelimit-unified-7d-status": "allowed", "request-id": "req_011CUabc"
    ]

    @Test func `a 429 while every quota allows requests may be the gate, and is still retried`() throws {
        let failure = try #require(
            AnthropicStreamDecoder.failure(inErrorBody: Self.rateLimited, status: 429, headers: Self.allowed))
        #expect(failure.kind == .rateLimited)
        #expect(ProviderFailure.isRetryable(status: 429, failure: failure))
        #expect(failure.message.contains("quotas still allow requests"), "\(failure.message)")
        #expect(failure.message.contains("the shape of the request"))
        #expect(failure.message.contains("req_011CUabc"))
        #expect(failure.message.contains("Anthropic said: Error"))
    }

    @Test func `a 429 without the subscription's headers keeps the provider's words`() throws {
        let failure = try #require(
            AnthropicStreamDecoder.failure(inErrorBody: Self.rateLimited, status: 429, headers: ["request-id": "req_1"])
        )
        #expect(failure.message == "Error")
        let window = Self.allowed.merging(["anthropic-ratelimit-unified-5h-status": "allowed_warning"]) { $1 }
        let warned = try #require(
            AnthropicStreamDecoder.failure(inErrorBody: Self.rateLimited, status: 429, headers: window))
        #expect(!warned.message.contains("quotas still allow"), "a window near its limit is not evidence of the gate")
    }

    @Test func `the credential refused outside Claude Code is said in words and not retried`() throws {
        // Reported publicly for subscription tokens sent without the expected identity; not met in ask's own recordings.
        let body = Array(
            #"{"type":"error","error":{"type":"invalid_request_error","message":"This credential is only authorized for use with Claude Code and cannot be used for other API requests."}}"#
                .utf8)
        let failure = try #require(
            AnthropicStreamDecoder.failure(inErrorBody: body, status: 400, headers: ["request-id": "req_2"]))
        #expect(
            failure.message.contains("refused this request's shape for a Claude subscription"), "\(failure.message)")
        #expect(
            failure.message.contains("req_2") && failure.message.contains("only authorized for use with Claude Code"))
        #expect(!ProviderFailure.isRetryable(status: 400, failure: failure))
    }

    @Test func `the out-of-extra-usage refusal carries the request id too`() throws {
        let failure = try #require(
            AnthropicStreamDecoder.failure(
                inErrorBody: AnthropicSubscriptionRefusalTests.body, status: 400, headers: ["request-id": "req_3"]))
        #expect(failure.message.contains("did not count this request") && failure.message.contains("req_3"))
    }
}
