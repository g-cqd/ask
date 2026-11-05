import Foundation
import Testing

@testable import AskAgentCore

/// Words a definition uses for a model that the listed ids do not match (roadmap 0063 phase 4, ADR-0146): a very cheap model on the
/// connection is asked which listed id they mean, given the words and the ids only; its answer counts only when it is one of them, and
/// each word's answer is kept so it is asked once.
@Suite("A cheap model maps a model word to a listed id, checked and kept")
struct ModelResolutionTests {
    private let listed = ["claude-opus-5-5", "claude-haiku-4-5", "claude-sonnet-5-5"]

    @Test func `the cheap model is the first listed whose name says it is small, or none`() {
        #expect(ModelResolution.cheapModel(in: listed) == "claude-haiku-4-5")
        #expect(ModelResolution.cheapModel(in: ["gpt-6-astra", "gpt-6-mini", "gpt-6-nano"]) == "gpt-6-mini")
        #expect(ModelResolution.cheapModel(in: ["claude-opus-5-5"]) == nil, "no cheap model, no request")
    }

    @Test func `the question holds the word and the ids, nothing else of the definition`() {
        let question = ModelResolution.question(word: "Fable", listed: listed)
        #expect(question.contains("Fable") && listed.allSatisfy(question.contains))
    }

    @Test func `an answer counts only when it is exactly a listed id`() {
        #expect(ModelResolution.answer(" `claude-opus-5-5`.\n", listed: listed) == "claude-opus-5-5")
        #expect(ModelResolution.answer("none", listed: listed) == nil)
        #expect(ModelResolution.answer("claude-opus-9", listed: listed) == nil, "not listed: nothing")
        #expect(ModelResolution.answer("I think claude-opus-5-5", listed: listed) == nil, "a sentence is not an answer")
    }

    @Test func `answers are kept by connection and word, a none too, and survive a reload`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "resolutions-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var cache = ModelResolution.Cache(path: path)
        #expect(cache.answer(provider: "anthropic", word: "fable") == nil)
        try cache.keep("claude-opus-5-5", provider: "anthropic", word: "Fable")
        try cache.keep(nil, provider: "anthropic", word: "Sage")
        let reloaded = ModelResolution.Cache(path: path)
        #expect(reloaded.answer(provider: "anthropic", word: "fable") == .some("claude-opus-5-5"), "any case")
        #expect(reloaded.answer(provider: "anthropic", word: "sage") == .some(nil), "asked, and nothing matched")
        #expect(reloaded.answer(provider: "codex", word: "fable") == nil, "another connection is asked again")
    }
}
