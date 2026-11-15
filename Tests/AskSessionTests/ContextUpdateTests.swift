import AskAI
import AskAgentCore
import AskTUI
import Synchronization
import Testing

@testable import AskSession

/// How full the context is, as the conversation says it: the status line's words, and the numbers behind them, for a driver
/// that shows them its own way (`ask serve` sends them as the protocol's usage; diary 2026-11-15-14).
@Suite("The context's occupancy is said in words and in numbers")
struct ContextUpdateTests {
    @Test func `measured, it carries the tokens of the last request and the model's window`() async throws {
        let fixture = try await ConversationFixture()
        fixture.conversation.current.withLock { $0.settings.model.contextWindow = 200_000 }
        fixture.conversation.usage.withLock {
            $0.add(TokenUsage(input: 40_000, output: 2000, cacheRead: 10_000, cacheCreation: 1000))
        }
        #expect(fixture.conversation.contextUpdate() == .context("26%/200k", used: 53_000, size: 200_000))
    }

    @Test func `what is not known is nil, not zero`() async throws {
        let fixture = try await ConversationFixture()
        fixture.conversation.current.withLock { $0.settings.model.contextWindow = 200_000 }
        #expect(
            fixture.conversation.contextUpdate() == .context("—%/200k", used: nil, size: 200_000),
            "nothing measured yet"
        )
        fixture.conversation.current.withLock { $0.settings.model.contextWindow = nil }
        fixture.conversation.usage.withLock { $0.add(TokenUsage(input: 5000, output: 100)) }
        #expect(
            fixture.conversation.contextUpdate() == .context("—%/?", used: 5100, size: nil),
            "a window nobody knows"
        )
    }
}
