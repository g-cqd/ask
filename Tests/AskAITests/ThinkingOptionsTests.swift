internal import Foundation
internal import Testing

@testable import AskAI

/// The efforts a list offers are the ones the model's own entry names, so a choice from it is accepted (ADR-0117).
@Suite("The thinking list offers what the model's catalog entry says it takes")
struct ThinkingOptionsTests {
    private let provider = URL(string: "https://example.com/v1")!

    @Test func `a Codex model offers its own levels, none as off, and marks its default`() {
        let entry = CatalogModel(
            id: "m", reasoningLevels: ["none", "low", "medium", "ultra"], defaultReasoningLevel: "medium")
        let choices = ThinkingOptions.choices(for: .codex, descriptor: entry)
        #expect(
            choices?.levels == [.off, .low, .medium],
            "ultra is advertised and refused by live inference, so it is not offered")
        #expect(choices?.verified == true)
        #expect(choices?.serverDefault == .medium)
    }

    @Test func `a model whose entry lists nothing offers what ask can send, said to be unverified`() {
        let choices = ThinkingOptions.choices(for: .codex, descriptor: nil)
        #expect(choices?.verified == false && choices?.levels.contains(.high) == true)
    }

    @Test func `a native model that cannot think offers nothing`() {
        let entry = CatalogModel(id: "m", supportsThinking: false)
        #expect(ThinkingOptions.choices(for: .anthropic, descriptor: entry) == nil)
    }

    @Test func `an adaptive native model offers its levels, and off when it can be disabled`() {
        let entry = CatalogModel(
            id: "m", reasoningLevels: ["low", "high"], supportsThinking: true, thinkingModes: [.adaptive, .disabled])
        #expect(ThinkingOptions.choices(for: .anthropic, descriptor: entry)?.levels == [.off, .low, .high])
    }

    @Test func `a budget-only native model offers the budget levels`() {
        let entry = CatalogModel(id: "m", supportsThinking: true, thinkingModes: [.enabled])
        let levels = ThinkingOptions.choices(for: .anthropic, descriptor: entry)?.levels
        #expect(levels == [.minimal, .low, .medium, .high, .xhigh, .max])
    }

    @Test func `protocols with no thinking control offer nothing`() {
        #expect(ThinkingOptions.choices(for: .apple, descriptor: nil) == nil)
        #expect(ThinkingOptions.choices(for: .agy, descriptor: nil) == nil)
        #expect(
            ThinkingOptions.choices(
                for: .openAICompatible(name: "x", baseURL: provider, apiKey: nil, headers: [:]), descriptor: nil) == nil
        )
    }

    @Test func `a level the catalog names that ask cannot send is left out`() {
        let entry = CatalogModel(id: "m", reasoningLevels: ["low", "warp"])
        #expect(ThinkingOptions.choices(for: .codex, descriptor: entry)?.levels == [.low])
    }
}
