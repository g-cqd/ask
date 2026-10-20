internal import Foundation
internal import Testing

@testable import AskAI

/// Where a provider's list is read from, and how what it says reaches a run (diary 55).
struct ProviderListingTests {
    private func settings(_ json: String) throws -> ProviderSettings {
        try ProviderSettings(decoding: Array(json.utf8))
    }

    private static let local = #"""
        {"providers":{"local":{"api":"openai-completions","baseUrl":"http://127.0.0.1:8181/v1/",
         "headers":{"x-team":"a"},"models":[{"id":"stated","contextWindow":9000,"maxTokens":900}]},
         "gateway":{"api":"openai-completions","baseUrl":"https://gw.example.test/v1","apiKey":"$GW_KEY"},
         "plain":{"api":"openai-completions","baseUrl":"http://gw.example.test/v1","apiKey":"literal"}}}
        """#

    @Test func `a preset is listed at its own address with the key its variable holds`() throws {
        let found = try ProviderSettings.none.listing(provider: "groq", environment: ["GROQ_API_KEY": "gsk-1"])
        #expect(found?.name == "groq")
        #expect(found?.baseURL.absoluteString == "https://api.groq.com/openai/v1")
        #expect(found?.apiKey == "gsk-1")
        #expect(found?.headers == [:])
    }

    @Test func `a configured provider keeps its headers, loses a trailing slash, and may have no key`() throws {
        let found = try settings(Self.local).listing(provider: "local", environment: [:])
        #expect(
            found
                == ProviderSettings.Listing(
                    name: "local", baseURL: URL(string: "http://127.0.0.1:8181/v1")!, apiKey: nil,
                    headers: ["x-team": "a"]))
    }

    @Test func `the default provider is listed when none is named`() throws {
        let value = try settings(
            #"{"default":"local","providers":{"local":{"api":"openai-completions","baseUrl":"http://127.0.0.1:1/v1"}}}"#
        )
        #expect(try value.listing(provider: nil, environment: [:])?.name == "local")
    }

    @Test func `a key comes from a variable the entry names, a sign-in, or nowhere, as for a run`() throws {
        #expect(try settings(Self.local).listing(provider: "gateway", environment: ["GW_KEY": "k"])?.apiKey == "k")
        #expect(throws: ProviderSettingsError.missingVariable(provider: "gateway", variable: "GW_KEY")) {
            try settings(Self.local).listing(provider: "gateway", environment: [:])
        }
        #expect(throws: ProviderSettingsError.missingVariable(provider: "groq", variable: "GROQ_API_KEY")) {
            try ProviderSettings.none.listing(provider: "groq", environment: [:])
        }
        let stored = try ProviderSettings.none.listing(
            provider: "mistral", environment: [:], storedKeys: { ["mistral": "vibe-key"] })
        #expect(stored?.apiKey == "vibe-key")
    }

    @Test func `a key is never sent to a plain-http address that is not on this machine`() throws {
        #expect(throws: ProviderSettingsError.self) {
            try settings(Self.local).listing(provider: "plain", environment: [:])
        }
    }

    @Test func `the built-in providers have their own catalogs and are not listed here`() throws {
        #expect(try ProviderSettings.none.listing(provider: "anthropic", environment: [:]) == nil)
        #expect(try ProviderSettings.none.listing(provider: "codex", environment: [:]) == nil)
        #expect(try ProviderSettings.none.listing(provider: nil, environment: [:]) == nil)
    }

    @Test func `an unknown provider is the same error a run gives`() {
        #expect(throws: ProviderSettingsError.self) {
            try ProviderSettings.none.listing(provider: "nosuch", environment: [:])
        }
    }

    // MARK: - What the list says reaches a run

    private static let listed = [
        CatalogModel(id: "org/big", contextWindow: 200_000, maxOutputTokens: 8000),
        CatalogModel(id: "stated", contextWindow: 1_000_000, maxOutputTokens: 5000),
        CatalogModel(id: "no-limits")
    ]

    @Test func `a model's listed limits reach the run when the user stated none`() throws {
        let resolved = try ProviderSettings.none.resolve(
            provider: "groq", model: "org/big", environment: ["GROQ_API_KEY": "k"], catalog: Self.listed)
        #expect(resolved.contextWindow == 200_000)
        #expect(resolved.maxOutputTokens == 8000)
    }

    @Test func `what the user stated wins over the list, field by field`() throws {
        let resolved = try settings(Self.local)
            .resolve(provider: "local", model: "stated", environment: [:], catalog: Self.listed)
        #expect(resolved.contextWindow == 9000)
        #expect(resolved.maxOutputTokens == 900)
        let half = try settings(
            #"{"providers":{"local":{"api":"openai-completions","baseUrl":"http://127.0.0.1:1/v1","models":[{"id":"stated","contextWindow":9000}]}}}"#
        )
        .resolve(provider: "local", model: "stated", environment: [:], catalog: Self.listed)
        #expect(half.contextWindow == 9000)
        #expect(half.maxOutputTokens == 5000, "a limit the user did not state is still the server's")
    }

    @Test func `a model the list does not name, or names without limits, keeps no invented ones`() throws {
        let env = ["GROQ_API_KEY": "k"]
        let absent = try ProviderSettings.none.resolve(
            provider: "groq", model: "other", environment: env, catalog: Self.listed)
        #expect(absent.contextWindow == nil && absent.maxOutputTokens == nil)
        let bare = try ProviderSettings.none.resolve(
            provider: "groq", model: "no-limits", environment: env, catalog: Self.listed)
        #expect(bare.contextWindow == nil && bare.maxOutputTokens == nil)
    }

    @Test func `a list never chooses the model for a provider`() {
        #expect(throws: ProviderSettingsError.noModel(provider: "groq")) {
            try ProviderSettings.none.resolve(
                provider: "groq", model: nil, environment: ["GROQ_API_KEY": "k"], catalog: Self.listed)
        }
    }
}
