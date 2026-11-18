import AskAI
import AskAgentCore
import AskTUI
import Testing

@testable import AskSession

/// A response the model refused (stop reason `refusal`) has no text: without a notice the screen shows nothing, and a person cannot
/// tell a refusal from ask having stopped (diary 2026-11-18).
@Suite("A refused answer is said, not shown as an empty one")
struct RefusalNoticeTests {
    @Test func `a refused answer is said as an error, live and when the session is resumed`() async throws {
        let fixture = try await ConversationFixture()
        let session = try fixture.newSession()
        _ = try session.append(.user("Continue."))
        let refused = AssembledResponse(
            id: "m",
            model: "any",
            blocks: [],
            stopReason: .refusal,
            usage: TokenUsage(),
            unrecognized: []
        )
        _ = try session.append(.response(refused))
        fixture.conversation.activateSession(session, update: fixture.update)
        let errors = fixture.conversation.history()
            .compactMap { update in if case .notice(let text, isError: true) = update { text } else { nil } }
        #expect(errors.count == 1 && errors[0].hasPrefix("any refused this request and said nothing"), "\(errors)")
        #expect(AgentConversation.updates(for: .responded(refused)) == [.notice(errors[0], isError: true)])
        var answered = refused
        answered.stopReason = .endTurn
        #expect(AgentConversation.updates(for: .responded(answered)).isEmpty)
    }
}
