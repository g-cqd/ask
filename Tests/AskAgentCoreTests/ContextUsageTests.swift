internal import AskAI
internal import Testing

@testable import AskAgentCore

@Suite("Context occupancy measures the last request, not session spend")
struct ContextUsageTests {
    @Test func `cached input and reply count toward the current window`() {
        var totals = UsageTotals()
        totals.add(TokenUsage(input: 20_000, output: 5_000, cacheRead: 20_000, cacheCreation: 5_000))
        #expect(totals.contextStatus(limit: 200_000) == "25%/200k")
        totals.add(TokenUsage(input: 1_000, output: 1_000))
        #expect(totals.contextStatus(limit: 200_000) == "1%/200k")
        #expect(totals.prompt == 46_000)
    }

    @Test func `unknown counts and capacities are not reported as zero`() {
        var totals = UsageTotals()
        #expect(totals.contextStatus(limit: 200_000) == "—%/200k")
        totals.add(TokenUsage(output: 100))
        #expect(totals.contextStatus(limit: 200_000) == "—%/200k")
        #expect(totals.contextStatus(limit: nil) == "—%/?")
        #expect(totals.contextStatus(limit: 0) == "—%/?")
    }

    @Test func `compaction does not mistake the summary request for the kept context`() {
        var totals = UsageTotals()
        totals.add(TokenUsage(input: 100_000, output: 1_000), isCompaction: true)
        #expect(totals.contextTokens == nil)
        #expect(totals.contextStatus(limit: 1_000_000) == "—%/1.0M")
        totals.add(TokenUsage(input: 50_000, output: 10_000))
        #expect(totals.contextStatus(limit: 1_000_000) == "6%/1.0M")
    }
}
