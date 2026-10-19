import AskAI
import Testing

@testable import AskAgentCore

@Suite("Usage sums responses and says what share of the prompt came from cache")
struct UsageTotalsTests {
    @Test func `responses add up, and the cached share counts reads over the whole prompt`() {
        var totals = UsageTotals()
        totals.add(TokenUsage(input: 4, output: 48, cacheRead: 0, cacheCreation: 1_040))
        totals.add(TokenUsage(input: 2, output: 7, cacheRead: 1_040, cacheCreation: 61))
        #expect(totals.prompt == 2_147)
        #expect(totals.output == 55)
        #expect(totals.summary == "in 2.1k (48% cached) · out 55")
    }

    @Test func `unreported counts add nothing, and an empty session says so plainly`() {
        var totals = UsageTotals()
        #expect(totals.summary == "in 0 (0% cached) · out 0")
        totals.add(TokenUsage(output: 3))
        #expect(totals.summary == "in 0 (0% cached) · out 3")
    }

    @Test(arguments: [(950, "950"), (1_249, "1.2k"), (13_400, "13k"), (1_420_000, "1.4M")])
    func `counts are shortened for a status line`(count: Int, text: String) {
        #expect(UsageTotals.short(count) == text)
    }
}
