import Testing

@testable import AskAgentCore

/// What `ask` prints when a run ends badly: a sentence saying what happened and what to change.
@Suite("Agent errors read as sentences")
struct AgentErrorDescriptionTests {
    @Test func `an overflow that compacting could not cure says what to change`() {
        let text = "\(AgentError.contextOverflow("the provider refused the request (HTTP 400): too long"))"
        #expect(text.contains("does not fit the model's context window"))
        #expect(text.contains("contextWindow"))
        #expect(text.contains("too long"))
    }

    @Test func `a provider failure is the provider's sentence, not a value dump`() {
        #expect("\(AgentError.provider("the provider answered HTTP 502"))" == "the provider answered HTTP 502")
    }

    @Test func `the turn limit names the option that raises it`() {
        #expect("\(AgentError.turnLimit(30))".contains("--max-turns"))
    }
}
