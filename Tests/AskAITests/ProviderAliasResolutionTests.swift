internal import Foundation
internal import Testing

@testable import AskAI

/// A named connection resolves its own aliases and default; nothing else does.
struct ProviderAliasResolutionTests {
    private func connection(_ kind: ConnectionKind = .codex) throws -> ConnectionRecord {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-alias-resolve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        return try ConnectionRegistry(directory: root).register(name: "work", provider: kind)
    }

    private func aliases() throws -> ModelAliases {
        var value = ModelAliases()
        try value.set("fast", to: "gpt-6-luna", contextWindow: 8000)
        try value.set("deep", to: "gpt-6-sol")
        return value
    }

    private let catalog = [
        CatalogModel(id: "gpt-6-luna", contextWindow: 272_000, maxOutputTokens: 4096),
        CatalogModel(id: "gpt-6-sol", contextWindow: 272_000)
    ]

    @Test func `an alias names the server's model, remembers the alias, and its stated window beats the catalog's`()
        throws
    {
        let work = try connection()
        let resolved = try ProviderSettings.none.resolve(
            provider: "work", model: "fast", environment: [:], catalog: catalog, connection: work,
            aliases: try aliases())
        #expect(resolved.model == "gpt-6-luna")
        #expect(resolved.alias == "fast")
        #expect(resolved.contextWindow == 8000, "the user's figure wins")
        #expect(resolved.maxOutputTokens == 4096, "and the catalog still supplies what the alias did not")
        #expect(resolved.connection == work)
    }

    @Test func `without an alias the catalog's own limits apply`() throws {
        let resolved = try ProviderSettings.none.resolve(
            provider: "work", model: "deep", environment: [:], catalog: catalog, connection: try connection(),
            aliases: try aliases())
        #expect(resolved.model == "gpt-6-sol" && resolved.alias == "deep" && resolved.contextWindow == 272_000)
    }

    @Test func `a connection's default model needs neither a flag nor the network`() throws {
        var value = try aliases()
        try value.setDefault("deep")
        let resolved = try ProviderSettings.none.resolve(
            provider: "work", model: nil, environment: [:], connection: try connection(), aliases: value)
        #expect(resolved.model == "gpt-6-sol" && resolved.alias == "deep")
    }

    @Test func `an explicit model beats the default, and a server id is not replaced`() throws {
        var value = try aliases()
        try value.setDefault("deep")
        let work = try connection()
        let explicit = try ProviderSettings.none.resolve(
            provider: "work", model: "fast", environment: [:], connection: work, aliases: value)
        #expect(explicit.model == "gpt-6-luna")
        let raw = try ProviderSettings.none.resolve(
            provider: "work", model: "gpt-9-unlisted", environment: [:], connection: work, aliases: value)
        #expect(raw.model == "gpt-9-unlisted" && raw.alias == nil)
    }

    @Test func `an alias that hides a model the account lists is refused with a sentence`() throws {
        var value = ModelAliases()
        try value.set("gpt-6-sol", to: "gpt-6-luna")
        #expect(throws: ProviderSettingsError.alias(.ambiguous("gpt-6-sol"))) {
            try ProviderSettings.none.resolve(
                provider: "work", model: "gpt-6-sol", environment: [:], catalog: catalog, connection: try connection(),
                aliases: value)
        }
    }

    @Test func `the default connection and other providers ignore aliases`() throws {
        let value = try aliases()
        let codex = try ProviderSettings.none.resolve(
            provider: "codex", model: "fast", environment: [:], catalog: catalog, aliases: value)
        #expect(codex.model == "fast" && codex.alias == nil, "an alias is not honoured without a named connection")
    }

    @Test func `a Claude connection resolves aliases with no catalog at all`() throws {
        var value = ModelAliases()
        try value.set("sonnet", to: "claude-sonnet-5-5")
        let resolved = try ProviderSettings.none.resolve(
            provider: "work", model: "sonnet", environment: [:], connection: try connection(.anthropic), aliases: value)
        #expect(resolved.model == "claude-sonnet-5-5" && resolved.alias == "sonnet")
    }
}
