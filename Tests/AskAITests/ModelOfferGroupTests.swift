internal import Testing

@testable import AskAI

/// Roadmap 0092: a model two accounts of one provider serve is one row of `/model`, with its accounts, not one row per account.
struct ModelOfferGroupTests {
    private func offer(_ account: String, _ kind: ConnectionKind?, _ model: String) -> ModelOffer {
        ModelOffer(account: account, kind: kind, model: model)
    }

    @Test func `one model of two accounts of one provider is one group, in the order the accounts came`() {
        let groups = ModelOfferGroup.grouped([
            offer("codex", .codex, "gpt-6"), offer("codex", .codex, "gpt-6-mini"), offer("codex-2", .codex, "gpt-6")
        ])
        #expect(groups.map(\.model) == ["gpt-6", "gpt-6-mini"])
        #expect(groups.map(\.accounts) == [["codex", "codex-2"], ["codex"]])
        #expect(groups[0].kind == .codex)
    }

    @Test func `the same id at different providers is not grouped`() {
        let groups = ModelOfferGroup.grouped([offer("codex", .codex, "m"), offer("anthropic", .anthropic, "m")])
        #expect(groups.map(\.accounts) == [["codex"], ["anthropic"]])
    }

    @Test func `providers reached with a key are never grouped`() {
        let groups = ModelOfferGroup.grouped([offer("groq", nil, "llama"), offer("openrouter", nil, "llama")])
        #expect(groups.map(\.accounts) == [["groq"], ["openrouter"]])
    }

    @Test func `an account listing a model twice counts once`() {
        let groups = ModelOfferGroup.grouped([offer("codex", .codex, "m"), offer("codex", .codex, "m")])
        #expect(groups.map(\.accounts) == [["codex"]])
    }
}
