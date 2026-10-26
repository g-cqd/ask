import AskAI
import Testing

@testable import AskAgentCore

/// A session's narrowing changes what the tools may do, never what the model is told: the prompt stays the stable prefix (ADR-0115).
@Suite("The model is never told the session's sandbox")
struct SessionNarrowingTests {
    @Test func `narrowing the session leaves the prompt as it was`() throws {
        let narrowing = SessionNarrowing()
        let loop = AgentLoop(
            provider: ScriptedProvider([]), tools: try ToolRegistry([]),
            settings: AgentSettings(
                model: "test", maximumTokens: 1_024, systemPrompt: ["Stable prefix."], maximumTurns: 4),
            context: ToolContext(workingDirectory: "/opt/ask-narrow", narrowing: narrowing))
        narrowing.policy = SandboxPolicy(network: .none, write: .roots([]))
        #expect(loop.request(for: [], events: { _ in }).systemPrompt == ["Stable prefix."])
        narrowing.policy = nil
        #expect(loop.request(for: [], events: { _ in }).systemPrompt == ["Stable prefix."])
    }
}
