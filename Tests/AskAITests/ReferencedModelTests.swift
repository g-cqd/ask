internal import Testing

@testable import AskAI

/// `provider/model` as a person writes it (ADR-0118): only a real provider's name before the first slash qualifies, so a model id with a slash is left alone.
@Suite("A model may be qualified by its provider, and only by a provider that exists")
struct ReferencedModelTests {
    private let names: Set<String> = ["codex", "anthropic", "openrouter", "Local"]

    @Test func `a bare model names no provider`() {
        let reference = ReferencedModel("gpt-6-sol", providers: names)
        #expect(reference.provider == nil && reference.model == "gpt-6-sol")
    }

    @Test func `a provider and a model split at the first slash`() {
        let reference = ReferencedModel("codex/gpt-6-sol", providers: names)
        #expect(reference.provider == "codex" && reference.model == "gpt-6-sol")
    }

    @Test func `a router's own slash stays in the model`() {
        #expect(ReferencedModel("openrouter/meta/llama-4", providers: names).model == "meta/llama-4")
        let bare = ReferencedModel("meta/llama-4", providers: names)
        #expect(bare.provider == nil && bare.model == "meta/llama-4")
    }

    @Test func `case does not matter in the provider, and claude is Anthropic`() {
        #expect(ReferencedModel("LOCAL/m", providers: names).provider == "local")
        let claude = ReferencedModel("claude/claude-sonnet-5-5", providers: names)
        #expect(claude.provider == "anthropic" && claude.model == "claude-sonnet-5-5")
    }

    @Test func `a provider with nothing after the slash is not a qualification`() {
        let reference = ReferencedModel("codex/", providers: names)
        #expect(reference.provider == nil && reference.model == "codex/")
    }
}
