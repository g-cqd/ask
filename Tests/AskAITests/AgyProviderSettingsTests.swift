internal import Foundation
internal import Testing

@testable import AskAI

/// Antigravity is a built-in provider beside Anthropic and Codex: it needs a model named (ask chooses none from the server's
/// list), no file may redefine it, and no named connection may take its name.
struct AgyProviderSettingsTests {
    private func resolve(
        _ json: String = "{}", provider: String? = nil, model: String? = nil
    ) throws -> ResolvedModel {
        try ProviderSettings(decoding: Array(json.utf8)).resolve(provider: provider, model: model, environment: [:])
    }

    @Test func `agy is built in, and needs a model named`() throws {
        let resolved = try resolve(provider: "agy", model: "gemini-3-flash")
        #expect(resolved.provider == .agy && resolved.model == "gemini-3-flash" && resolved.connection == nil)
        #expect(throws: ProviderSettingsError.noModel(provider: "agy")) { try resolve(provider: "agy") }
    }

    @Test func `a catalog supplies the limits of the model named, and does not choose one`() throws {
        let catalog = [CatalogModel(id: "m1", contextWindow: 1_000, maxOutputTokens: 100), CatalogModel(id: "m2")]
        let settings = ProviderSettings.none
        let chosen = try settings.resolve(provider: "agy", model: "m1", environment: [:], catalog: catalog)
        #expect(chosen.contextWindow == 1_000 && chosen.maxOutputTokens == 100)
        #expect(throws: ProviderSettingsError.noModel(provider: "agy")) {
            try settings.resolve(provider: "agy", model: nil, environment: [:], catalog: catalog)
        }
    }

    @Test func `a missing model says to list the account's and pass one`() {
        let text = ProviderSettingsError.noModel(provider: "agy").description
        #expect(text.contains("ask models agy") && text.contains("--model") && !text.contains("add one"))
    }

    @Test func `a file may not define agy, which is built in`() {
        let json = #"{ "providers": { "agy": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:1/v1" } } }"#
        #expect(throws: ProviderSettingsError.reservedName("agy")) { try resolve(json, provider: "agy", model: "m") }
    }

    @Test func `agy is the file's default when it says so, and is listed among the known`() throws {
        #expect(try resolve(#"{ "default": "agy" }"#, model: "m").provider == .agy)
        #expect(ProviderSettings.none.known(environment: [:], stored: [:]).prefix(3) == ["anthropic", "codex", "agy"])
    }

    @Test func `agy has no OpenAI-compatible listing to read`() throws {
        #expect(try ProviderSettings.none.listing(provider: "agy", environment: [:]) == nil)
    }

    @Test func `no named connection may take the name agy`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-agy-name-\(UUID().uuidString)")
        let registry = ConnectionRegistry(directory: directory)
        #expect(throws: ConnectionError.nameInUse("agy")) { try registry.register(name: "agy", provider: .codex) }
    }

    @Test func `an explicit thinking level is refused for agy, and the default is not`() throws {
        let model = ResolvedModel(provider: .agy, model: "gemini-3-flash")
        #expect(throws: ThinkingError.unsupportedProtocol("Antigravity")) {
            try ThinkingControl.select(.high, model: model, descriptor: nil, maximumTokens: 10_000)
        }
        #expect(
            try ThinkingControl.select(.providerDefault, model: model, descriptor: nil, maximumTokens: 10_000) == nil)
    }

    @Test func `a registration called agy is refused, as one called codex is`() throws {
        for name in ["agy", "codex"] {
            let record = ConnectionRecord(name: name, provider: .codex)
            #expect(throws: ProviderSettingsError.reservedName(name)) {
                try ProviderSettings.none.resolve(
                    provider: name, model: "m", environment: [:], connection: record)
            }
        }
    }
}
