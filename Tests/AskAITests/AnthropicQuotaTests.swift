import Testing

@testable import AskAI

@Suite("Quota headers explain subscription refusals")
struct AnthropicQuotaTests {
    @Test(arguments: ["5h", "7d", "7d-sonnet", "7d-opus", ""])
    func `a rejected quota is a usage limit and is not retried`(window: String) async throws {
        let stem = "anthropic-ratelimit-unified-" + (window.isEmpty ? "" : window + "-")
        let transport = ScriptedTransport(
            status: 429,
            chunks: [#"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}"#],
            headers: [
                stem + "status": "rejected", stem + "reset": "1793160000",
                "anthropic-ratelimit-unified-overage-disabled-reason": "org_level_disabled"
            ])
        let sut = AnthropicClient(transport: transport)
        let request = ModelRequest(model: "m", maxTokens: 16, systemPrompt: [], messages: [], tools: [])
        do {
            for try await _ in sut.stream(request, auth: .subscription(accessToken: "test")) {}
            #expect(Bool(false), "expected a rejection")
        } catch let error as AnthropicClientError {
            guard case .status(429, let failure?, _) = error else {
                #expect(Bool(false), "unexpected \(error)")
                return
            }
            #expect(failure.kind == .usageLimit)
            #expect(!error.isRetryable)
            #expect(failure.sentence.contains("2026-10-28T04:00:00Z"))
            #expect(failure.sentence.contains("organization"))
        }
    }

    @Test(arguments: ["", "NaN", "Infinity", "-1", "1e100"])
    func `quota rejection survives an unreadable body and invalid reset`(reset: String) {
        let failure = AnthropicStreamDecoder.failure(
            inErrorBody: [], status: 429,
            headers: [
                "anthropic-ratelimit-unified-7d-status": "rejected",
                "anthropic-ratelimit-unified-7d-reset": reset
            ])
        #expect(failure?.kind == .usageLimit)
        #expect(failure?.message.contains("weekly") == true)
    }

    @Test(arguments: [
        [String: String](), ["anthropic-ratelimit-unified-7d-utilization": "1.0"],
        ["anthropic-ratelimit-unified-7d-status": "allowed"],
        ["anthropic-ratelimit-unified-7d-status": "rejected", "anthropic-ratelimit-unified-overage-status": "allowed"]
    ])
    func `inconclusive quotas retain the rate limit classification`(headers: [String: String]) {
        let body = Array(#"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}"#.utf8)
        #expect(AnthropicStreamDecoder.failure(inErrorBody: body, status: 429, headers: headers)?.kind == .rateLimited)
        #expect(AnthropicStreamDecoder.failure(inErrorBody: [], status: 401, headers: headers) == nil)
    }
}
