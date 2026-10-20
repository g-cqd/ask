internal import Foundation
internal import Testing

@testable import AskAI

/// A usage limit is not a rate limit. A rate limit clears in seconds and is worth another try; a usage limit lifts at a set time,
/// often hours away, and four retries over fifteen seconds only delay the answer. Found on a real account: ChatGPT's 429 body
/// says `usage_limit_reached` and how many seconds are left.
struct UsageLimitTests {
    private func failure(_ json: String) -> ProviderFailure? {
        OpenAIStreamDecoder.failure(inErrorBody: Array(json.utf8))
    }

    private var recorded: String {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Codex/usage-limit-429.json")
        return String(decoding: (try? Data(contentsOf: path)) ?? Data(), as: UTF8.self)
    }

    @Test func `the recorded ChatGPT usage limit is a usage limit with its seconds, and is not retried`() {
        let reason = failure(recorded)
        #expect(reason?.kind == .usageLimit)
        #expect(reason?.resetsInSeconds == 1181)
        #expect(ProviderFailure.isRetryable(status: 429, failure: reason) == false)
        #expect(reason?.sentence == "The usage limit has been reached; it resets in about 20 minutes")
    }

    @Test func `a usage limit with no reset time still stops retrying, and says only what the server said`() {
        let reason = failure(#"{"error":{"type":"usage_limit_reached","message":"The usage limit has been reached"}}"#)
        #expect(reason?.kind == .usageLimit)
        #expect(reason?.resetsInSeconds == nil)
        #expect(reason?.sentence == "The usage limit has been reached")
        #expect(ProviderFailure.isRetryable(status: 429, failure: reason) == false)
    }

    @Test func `OpenAI's insufficient quota is a usage limit too`() {
        let reason = failure(
            #"{"error":{"type":"insufficient_quota","code":"insufficient_quota","message":"You exceeded your current quota"}}"#
        )
        #expect(reason?.kind == .usageLimit)
        #expect(ProviderFailure.isRetryable(status: 429, failure: reason) == false)
    }

    @Test func `an ordinary rate limit is still retried, with or without a body`() {
        let named = failure(#"{"error":{"type":"rate_limit_exceeded","message":"Slow down"}}"#)
        #expect(named?.kind == .rateLimited)
        #expect(ProviderFailure.isRetryable(status: 429, failure: named))
        #expect(ProviderFailure.isRetryable(status: 429, failure: nil))
        #expect(ProviderFailure.isRetryable(status: 503, failure: nil))
        let quotaWord = failure(#"{"error":{"type":"quota_exceeded_per_minute","message":"Too many requests"}}"#)
        #expect(quotaWord?.kind == .rateLimited, "only the two named usage-limit types are treated as one")
    }

    @Test func `a plain rate limit never claims a reset time`() {
        let reason = failure(#"{"error":{"type":"rate_limit_exceeded","message":"Slow down","resets_in_seconds":30}}"#)
        #expect(reason?.resetsInSeconds == nil)
        #expect(reason?.sentence == "Slow down")
    }

    @Test(arguments: [#"-5"#, #"2592001"#, #""soon""#, #"1181.5"#, #"null"#, #"[1]"#, #"{"a":1}"#, #"true"#])
    func `a reset time that is not a sensible number of seconds is ignored, not trusted`(_ value: String) {
        let reason = failure(
            #"{"error":{"type":"usage_limit_reached","message":"Limit","resets_in_seconds":\#(value)}}"#)
        #expect(reason?.kind == .usageLimit)
        #expect(reason?.resetsInSeconds == nil)
        #expect(reason?.sentence == "Limit")
    }

    @Test func `the largest and smallest sensible reset times are kept`() {
        let top = failure(#"{"error":{"type":"usage_limit_reached","message":"L","resets_in_seconds":2592000}}"#)
        #expect(top?.resetsInSeconds == 2_592_000)
        let zero = failure(#"{"error":{"type":"usage_limit_reached","message":"L","resets_in_seconds":0}}"#)
        #expect(zero?.resetsInSeconds == 0)
        #expect(zero?.sentence == "L; it resets in less than a minute")
    }

    @Test(arguments: [
        (0, "less than a minute"), (59, "less than a minute"), (60, "about 1 minute"), (89, "about 1 minute"),
        (90, "about 2 minutes"), (1181, "about 20 minutes"), (3569, "about 59 minutes"), (3570, "about 1 hour"),
        (5399, "about 1 hour"), (5400, "about 2 hours"), (86_399, "about 24 hours"), (86_400, "about 1 day"),
        (172_800, "about 2 days"), (2_592_000, "about 30 days")
    ])
    func `a duration is told as a person would, to the nearest minute, hour or day`(seconds: Int, text: String) {
        let reason = ProviderFailure(kind: .usageLimit, message: "L", resetsInSeconds: seconds)
        #expect(reason.sentence == "L; it resets in \(text)")
    }

    @Test func `the error a person reads says when it lifts, in both places a failure can surface`() {
        let reason = failure(recorded)
        let status = OpenAICompatibleError.status(429, reason, retryAfter: nil)
        #expect(
            status.description
                == "the provider refused the request (HTTP 429): The usage limit has been reached; it resets in about 20 minutes"
        )
        #expect(status.isRetryable == false)
        #expect(status.retryAfter == nil)
        let stream = OpenAICompatibleError.stream(.provider(try! #require(reason)))
        #expect(stream.description.contains("it resets in about 20 minutes"))
    }

    @Test func `other kinds keep the provider's words exactly`() {
        for kind: ProviderFailure.Kind in [.overloaded, .rateLimited, .authentication, .server, .other("x")] {
            #expect(ProviderFailure(kind: kind, message: "Their words", resetsInSeconds: 99).sentence == "Their words")
        }
    }
}
