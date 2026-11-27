internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Testing

@testable import AskSession

/// Owner, 2026-11-27: where another model starts answering, a gray line says so, live and when the session is shown again; the first
/// model of a conversation is not a change.
@Suite("A change of model is shown where it starts")
struct ModelChangeShownTests {
    private static func destination(_ model: String, name: String = ProviderSettings.anthropic) -> SessionDestination {
        SessionDestination(connectionID: name, authorizationID: nil, name: name, model: model)
    }

    @Test func `the line names the model as the status line does`() {
        #expect(
            AgentConversation.answersFromHere(Self.destination("claude-b"))
                == .notice("claude-b answers from here.", isError: false)
        )
        #expect(
            AgentConversation.answersFromHere(Self.destination("gpt-6", name: "codex"))
                == .notice("codex/gpt-6 answers from here.", isError: false)
        )
    }

    @Test func `a resumed conversation shows the change where it was recorded, and not the first model`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        try recorder.select(Self.destination("claude-a"), explicitlySelected: true)
        _ = try recorder.append(.user("one"))
        _ = try recorder.append(.assistant("from a"))
        try recorder.select(Self.destination("claude-b"), explicitlySelected: true)
        _ = try recorder.append(.user("two"))
        _ = try recorder.append(.assistant("from b"))
        let shown = fixture.conversation.replayed(recorder.tree.activeBranch(), after: nil, placing: [])
        let lines = shown.compactMap { update -> String? in
            switch update {
                case .notice(let text, _): text
                case .userPrompt(let text): "> " + text
                default: nil
            }
        }
        #expect(lines == ["> one", "claude-b answers from here.", "> two"])
    }

    @Test func `live, a run that selects another model says so, and the first selection does not`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        var said: [ConversationUpdate] = []
        AgentConversation.noteModelChange(from: nil, in: recorder) { said.append($0) }
        try recorder.select(Self.destination("claude-a"), explicitlySelected: true)
        AgentConversation.noteModelChange(from: nil, in: recorder) { said.append($0) }
        let before = recorder.destination
        try recorder.select(Self.destination("claude-a"), explicitlySelected: true)
        AgentConversation.noteModelChange(from: before, in: recorder) { said.append($0) }
        try recorder.select(Self.destination("claude-b"), explicitlySelected: true)
        AgentConversation.noteModelChange(from: before, in: recorder) { said.append($0) }
        #expect(said == [.notice("claude-b answers from here.", isError: false)])
    }
}
