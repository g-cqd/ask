internal import Testing

@testable import AskAI

struct ProviderCatalogResolutionTests {
    private static let catalog = [
        CatalogModel(id: "recommended", contextWindow: 500_000),
        CatalogModel(id: "small", contextWindow: 32_768, maxOutputTokens: 4096)
    ]

    @Test func `a catalog supplies the Codex default and its normal limits`() throws {
        let model = try ProviderSettings.none.resolve(
            provider: "codex", model: nil, environment: [:], catalog: Self.catalog)
        #expect(model == ResolvedModel(provider: .codex, model: "recommended", contextWindow: 500_000))
    }

    @Test func `an explicit model wins and takes only its own catalog limits`() throws {
        let model = try ProviderSettings.none.resolve(
            provider: "codex", model: "small", environment: [:], catalog: Self.catalog)
        #expect(model == ResolvedModel(provider: .codex, model: "small", contextWindow: 32_768, maxOutputTokens: 4096))
        let unlisted = try ProviderSettings.none.resolve(
            provider: "codex", model: "unlisted", environment: [:], catalog: Self.catalog)
        #expect(unlisted == ResolvedModel(provider: .codex, model: "unlisted"))
    }

    @Test func `a catalog is not an implicit default for an unrelated provider`() throws {
        let model = try ProviderSettings.none.resolve(
            provider: "anthropic", model: nil, environment: [:], catalog: Self.catalog)
        #expect(model.provider == .anthropic)
        #expect(model.model == ProviderSettings.anthropicDefaultModel)
        #expect(model.contextWindow == nil)
    }
}
