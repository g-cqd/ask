import Testing

@testable import AskAI

/// Anthropic answers HTTP 400 "You're out of extra usage" when it does not count a request against the Claude subscription and extra usage
/// is off (roadmap 0144). The words read like a spent quota; the person is told what happened instead, and that sending it again will not help.
@Suite("A request the subscription does not cover says so")
struct AnthropicSubscriptionRefusalTests {
    static let body = Array(
        #"{"type":"error","error":{"type":"invalid_request_error","message":"You're out of extra usage. Add more at claude.ai/settings/usage and keep going."}}"#
            .utf8)

    @Test func `the refusal says the subscription did not cover the request`() throws {
        let failure = try #require(
            AnthropicStreamDecoder.failure(
                inErrorBody: Self.body, status: 400,
                headers: [
                    "anthropic-ratelimit-unified-5h-status": "allowed",
                    "anthropic-ratelimit-unified-overage-disabled-reason": "org_level_disabled"
                ]))
        #expect(failure.kind == .invalidRequest)
        #expect(failure.message.contains("did not count this request against your Claude subscription"))
        #expect(failure.message.contains("five-hour quota still allows requests"))
        #expect(failure.message.contains("Sending it again will not help"))
        #expect(failure.message.contains("You're out of extra usage"))
        #expect(!ProviderFailure.isRetryable(status: 400, failure: failure))
    }

    @Test func `without quota headers it does not claim the quota is left`() throws {
        let failure = try #require(AnthropicStreamDecoder.failure(inErrorBody: Self.body, status: 400, headers: [:]))
        #expect(failure.message.contains("did not count this request"))
        #expect(!failure.message.contains("still allows"))
    }

    @Test func `other invalid requests keep the provider's words`() {
        let body = Array(
            #"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: too large"}}"#.utf8)
        #expect(
            AnthropicStreamDecoder.failure(inErrorBody: body, status: 400, headers: [:])?.message
                == "max_tokens: too large")
    }
}
