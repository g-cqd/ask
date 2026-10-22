import AskAI
import Testing

@testable import AskAgentCore

/// The current policy is repeated beside the stable prompt, even when compaction has removed the tool result.
@Suite("The model sees the session's current sandbox on every request")
struct SessionNarrowingTests {
    @Test func `the active policy follows the session without rewriting the stable prefix`() throws {
        let narrowing = SessionNarrowing()
        let loop = AgentLoop(
            provider: ScriptedProvider([]), tools: try ToolRegistry([]),
            settings: AgentSettings(
                model: "test", maximumTokens: 1_024, systemPrompt: ["Stable prefix."], maximumTurns: 4),
            context: ToolContext(workingDirectory: "/opt/ask-narrow", narrowing: narrowing))
        #expect(loop.request(for: [], events: { _ in }).systemPrompt == ["Stable prefix."])
        narrowing.policy = SandboxPolicy(network: .none, write: .roots([]))
        let prompt = loop.request(for: [], events: { _ in }).systemPrompt
        #expect(prompt.first == "Stable prefix." && prompt.count == 2)
        #expect(prompt.last?.contains("There is no network access.") == true)
        #expect(prompt.last?.contains("Writes are allowed only under nowhere but temporary directories.") == true)
        narrowing.policy = nil
        #expect(loop.request(for: [], events: { _ in }).systemPrompt == ["Stable prefix."])
    }
}
