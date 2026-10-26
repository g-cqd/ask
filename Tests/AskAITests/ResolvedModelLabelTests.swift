import Foundation
import Testing

@testable import AskAI

/// How a model is named to the person (roadmap 0028): `model` for the built-in Anthropic provider, and `provider/model` for every other.
@Suite("A model's label names its provider unless it is the default one")
struct ResolvedModelLabelTests {
    private let url = URL(string: "https://example.test/v1")!

    @Test func `the built-in provider is the bare model`() {
        #expect(ResolvedModel(provider: .anthropic, model: "claude-sonnet-5-5").label == "claude-sonnet-5-5")
    }

    @Test func `codex and agy are prefixed with their names`() {
        #expect(ResolvedModel(provider: .codex, model: "gpt-x").label == "codex/gpt-x")
        #expect(ResolvedModel(provider: .agy, model: "gemini-y").label == "agy/gemini-y")
    }

    @Test func `a configured provider is prefixed with the name the configuration gave it`() {
        let chat = ResolvedModel(
            provider: .openAICompatible(name: "local", baseURL: url, apiKey: nil, headers: [:]), model: "llama")
        let responses = ResolvedModel(
            provider: .openAIResponses(name: "gateway", baseURL: url, apiKey: nil, headers: [:]), model: "gpt")
        #expect(chat.label == "local/llama" && responses.label == "gateway/gpt")
    }

    @Test func `a named connection wins over the provider's own name`() {
        var model = ResolvedModel(provider: .codex, model: "gpt-x")
        model.connection = ConnectionRecord(name: "work", provider: .codex)
        #expect(model.label == "work/gpt-x")
    }
}
