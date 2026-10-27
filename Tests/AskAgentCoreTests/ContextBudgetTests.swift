import Testing

@testable import AskAgentCore

/// A model's context window decides how much it may write, when the conversation is compacted and how much a
/// compaction keeps, so a 32k local model compacts before it is refused instead of after.
@Suite("The context budget follows the model's window")
struct ContextBudgetTests {
    @Test func `with no window known, the long-standing defaults hold`() {
        let budget = ContextBudget(contextWindow: nil, maxOutputTokens: nil, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 16_384)
        #expect(budget.compactAtTokens == 150_000)
        #expect(budget.keepRecentBytes == 80_000)
        #expect(budget.toolOutputBytes == nil)
    }

    @Test func `a 32k window compacts well before it is full, and keeps a tail that fits`() throws {
        let budget = ContextBudget(contextWindow: 32_768, maxOutputTokens: nil, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 8_192)
        #expect(budget.compactAtTokens == 32_768 - 8_192 - 4_096)
        #expect(budget.keepRecentBytes == 32_768)
        #expect(budget.toolOutputBytes == 32_768)
        // The threshold plus a reply always fits the window.
        #expect(try #require(budget.compactAtTokens) + budget.maximumTokens < 32_768)
    }

    @Test func `a large window keeps the defaults it has room for`() {
        let budget = ContextBudget(contextWindow: 1_000_000, maxOutputTokens: 64_000, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 64_000)
        #expect(budget.compactAtTokens == 150_000)
        #expect(budget.keepRecentBytes == 80_000)
    }

    @Test func `the model's own output limit is honoured when it is lower`() {
        let budget = ContextBudget(contextWindow: 128_000, maxOutputTokens: 4_096, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 4_096)
        #expect(budget.compactAtTokens == 128_000 - 4_096 - 12_800)
    }

    @Test func `compaction turned off stays off; the overflow path covers it`() {
        let budget = ContextBudget(contextWindow: 32_768, maxOutputTokens: nil, requestedCompactAt: nil)
        #expect(budget.compactAtTokens == nil)
    }

    @Test func `a lower threshold the user asked for wins`() {
        let budget = ContextBudget(contextWindow: 32_768, maxOutputTokens: nil, requestedCompactAt: 10_000)
        #expect(budget.compactAtTokens == 10_000)
    }

    @Test func `the on-device window's margin floors the compaction threshold`() {
        // 4,096 tokens with a 1,024-token reply: the margin's least (4,096) leaves nothing of the window, so
        // compaction is due from the first response. The loop does not attempt one while the conversation fits
        // the kept tail (diary 2026-10-28); this pins the floor it compensates for.
        let budget = ContextBudget(contextWindow: 4_096, maxOutputTokens: 1_024, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 1_024)
        #expect(budget.compactAtTokens == 1)
        #expect(budget.keepRecentBytes == 4_096)
    }

    @Test func `a window too small to hold a reply still yields a usable budget`() {
        let budget = ContextBudget(contextWindow: 2_048, maxOutputTokens: nil, requestedCompactAt: 150_000)
        #expect(budget.maximumTokens == 512)
        #expect((budget.compactAtTokens ?? 0) >= 1)
        #expect(budget.keepRecentBytes >= 1)
    }
}
