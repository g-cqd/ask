internal import Testing

@testable import AskApple

/// How a small window is shared: a reply never takes more than a quarter, and the conversation always keeps something.
@Suite("The on-device window is shared so the conversation always has room")
struct AppleBudgetTests {
    @Test func `a reply is what was asked for, but never more than a quarter of the window`() {
        #expect(AppleBudget(window: 4096, requested: 512).reply == 512)
        #expect(AppleBudget(window: 4096, requested: 32_000).reply == 1024)
    }

    @Test func `a reply always has a floor`() { #expect(AppleBudget(window: 100, requested: 1).reply == 64) }

    @Test func `the tools may take half the window, so every tool can be offered`() {
        #expect(AppleBudget(window: 8192, requested: 1024).toolTokens == 4096)
    }

    @Test func `the instructions get what the conversation's floor leaves, and never less than a fifth`() {
        let budget = AppleBudget(window: 8192, requested: 1024)
        #expect(budget.instructionTokens(tools: 500) == 8192 - 1024 - 500 - 2048 - 64)
        #expect(budget.instructionTokens(tools: 4096) == 8192 / 5, "a crowded window still keeps a fifth")
    }

    @Test func `the conversation gets what the others leave, and never less than an eighth`() {
        let budget = AppleBudget(window: 4096, requested: 1024)
        #expect(budget.conversationTokens(instructions: 100, tools: 200) == 4096 - 1024 - 100 - 200 - 64)
        #expect(budget.conversationTokens(instructions: 3000, tools: 3000) == 512)
    }
}
