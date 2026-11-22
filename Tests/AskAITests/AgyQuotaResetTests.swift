import Testing

@testable import AskAI

/// An Antigravity quota that names when it lifts is a usage limit, not retried and said with its reset; a per-minute rate limit stays
/// a rate limit (t117). The wording is the one recorded on the account, 2026-11-12 (diary 2026-11-12-04).
@Suite("An Antigravity quota with a reset is a usage limit")
struct AgyQuotaResetTests {
    private static func failure(_ message: String, code: Int = 429) -> ProviderFailure? {
        let body = #"{"error":{"code":\#(code),"message":"\#(message)","status":"RESOURCE_EXHAUSTED"}}"#
        return AgyStreamDecoder.failure(inErrorBody: Array(body.utf8))
    }

    @Test func `the recorded quota is a usage limit that lifts in 90 h 38 min, and is not retried`() throws {
        let quota = try #require(
            Self.failure(
                "Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 90h38m"
            )
        )
        #expect(quota.kind == .usageLimit && quota.resetsInSeconds == 90 * 3_600 + 38 * 60)
        #expect(
            quota.sentence
                == "Individual quota reached. Please upgrade your subscription to increase your limits; it resets in about 4 days"
        )
        #expect(!ProviderFailure.isRetryable(status: 429, failure: quota))
    }

    @Test func `a rate limit without a reset stays one, and is retried`() throws {
        let limit = try #require(Self.failure("Quota exceeded for quota metric 'Requests per minute'."))
        #expect(limit.kind == .rateLimited && ProviderFailure.isRetryable(status: 429, failure: limit))
        let other = try #require(Self.failure("Resets in 5m", code: 400))
        #expect(other.kind == .invalidRequest, "only a 429 is read for a reset")
    }

    @Test func `durations read in d, h, m and s, in order; anything else is no reset`() {
        #expect(AgyQuotaReset.reading("x. Resets in 2d3h.")?.seconds == 2 * 86_400 + 3 * 3_600)
        #expect(AgyQuotaReset.reading("Resets in 45s")?.seconds == 45)
        #expect(AgyQuotaReset.reading("Resets in 38m12s, then")?.seconds == 38 * 60 + 12)
        #expect(AgyQuotaReset.reading("Resets in 38m12s, then")?.message == "")
        for bad in [
            "Resets in soon", "Resets in 5", "Resets in 3m2h", "Resets in 1x", "Resets in ", "no phrase",
            "Resets in 1234567890s"
        ] {
            #expect(AgyQuotaReset.reading(bad) == nil, "\(bad)")
        }
    }
}
