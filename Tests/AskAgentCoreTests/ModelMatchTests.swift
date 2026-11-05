import Testing

@testable import AskAgentCore

/// A definition's model preference matched against what the connection lists (roadmap 0063 phase 3, ADR-0146): an id, a display name
/// written any way, or a family word, in the file's order; nothing that matches means the parent's model, never a guess.
@Suite("A definition's model words are matched against the listed models")
struct ModelMatchTests {
    private let listed = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-haiku-3-5"]

    @Test func `an id, then a display name written any way, then a family word, in the file's order`() {
        #expect(ModelMatch.first(of: ["claude-sonnet-5-5"], in: listed) == "claude-sonnet-5-5")
        #expect(ModelMatch.first(of: ["Claude Opus 5.5"], in: listed) == "claude-opus-5-5")
        #expect(ModelMatch.first(of: ["haiku"], in: listed) == "claude-haiku-4-5", "the first listed of the family")
        #expect(
            ModelMatch.first(of: ["gpt-6-astra", "sonnet"], in: listed) == "claude-sonnet-5-5",
            "a fallback after one not listed"
        )
    }

    @Test func `nothing that matches is nil, and a word is not matched inside another`() {
        #expect(ModelMatch.first(of: ["gpt-6-astra"], in: listed) == nil)
        #expect(ModelMatch.first(of: ["son"], in: listed) == nil, "a part of a word is not a family")
        #expect(ModelMatch.first(of: [], in: listed) == nil)
    }
}
