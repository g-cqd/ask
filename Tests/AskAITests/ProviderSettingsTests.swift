internal import Foundation
internal import Testing

@testable import AskAI

/// `providers.json` connects ask to any OpenAI-compatible endpoint without code, in the shape pi's `models.json` uses.
@Suite("Provider settings choose the provider and model, and never leak a credential")
struct ProviderSettingsTests {
    private static let local = #"""
        {
          "default": "local",
          "providers": {
            "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:8181/v1",
                       "models": [{ "id": "ornith" }, { "id": "gemma" }] },
            "lan": { "api": "openai-completions", "baseUrl": "http://10.0.0.5:11434/v1", "defaultModel": "qwen" },
            "hosted": { "api": "openai-completions", "baseUrl": "https://gw.example/v1", "apiKey": "${GW_KEY}",
                        "headers": { "x-org": "o" }, "models": [{ "id": "big" }] }
          }
        }
        """#

    private func settings(_ json: String = local) throws -> ProviderSettings {
        try ProviderSettings(decoding: Array(json.utf8))
    }

    private func resolve(
        _ json: String = local, provider: String? = nil, model: String? = nil, environment: [String: String] = [:]
    ) throws -> ResolvedModel {
        try settings(json).resolve(provider: provider, model: model, environment: environment)
    }

    @Test func `no settings at all means Anthropic and Claude's default model`() throws {
        let resolved = try ProviderSettings.none.resolve(provider: nil, model: nil, environment: [:])
        #expect(resolved.provider == .anthropic)
        #expect(resolved.model == ProviderSettings.anthropicDefaultModel)
    }

    @Test func `the file's default provider is used, with its first model`() throws {
        let resolved = try resolve()
        #expect(resolved.model == "ornith")
        guard case .openAICompatible(let name, let url, let key, _) = resolved.provider else {
            Issue.record("not an OpenAI-compatible provider: \(resolved.provider)")
            return
        }
        #expect(name == "local")
        #expect(url.absoluteString == "http://127.0.0.1:8181/v1")
        #expect(key == nil)
    }

    @Test func `an explicit model and provider win, and anthropic is always available`() throws {
        #expect(try resolve(model: "gemma").model == "gemma")
        #expect(try resolve(provider: "lan").model == "qwen")
        #expect(try resolve(provider: "anthropic").provider == .anthropic)
        #expect(try resolve(provider: "anthropic").model == ProviderSettings.anthropicDefaultModel)
    }

    @Test func `a key is read from the environment, with the headers`() throws {
        let resolved = try resolve(provider: "hosted", environment: ["GW_KEY": "sk-9"])
        guard case .openAICompatible(_, _, let key, let headers) = resolved.provider else {
            Issue.record("not an OpenAI-compatible provider")
            return
        }
        #expect(key == "sk-9")
        #expect(headers == ["x-org": "o"])
    }

    @Test func `a key from an unset variable is an error, never an empty key`() {
        #expect(throws: ProviderSettingsError.self) { try resolve(provider: "hosted", environment: [:]) }
    }

    @Test func `an unknown provider is an error that names the ones that exist`() throws {
        do {
            _ = try resolve(provider: "nope")
            Issue.record("an unknown provider resolved")
        } catch let error as ProviderSettingsError {
            #expect("\(error)".contains("local"))
            #expect("\(error)".contains("anthropic"))
        }
    }

    @Test func `a credential over plain http to another machine is refused`() {
        let json = #"{"providers":{"x":{"api":"openai-completions","baseUrl":"http://10.0.0.5/v1","apiKey":"sk"}}}"#
        #expect(throws: ProviderSettingsError.self) { try resolve(json, provider: "x") }
    }

    @Test func `plain http without a key is allowed to another machine, as a LAN server needs`() throws {
        #expect(try resolve(provider: "lan").model == "qwen")
    }

    @Test(arguments: [
        #"{"providers":{"x":{"api":"anthropic-messages","baseUrl":"https://a/v1","models":[{"id":"m"}]}}}"#,
        #"{"providers":{"x":{"api":"openai-completions","baseUrl":"ftp://a/v1","models":[{"id":"m"}]}}}"#,
        #"{"providers":{"x":{"api":"openai-completions","baseUrl":"https://a/v1"}}}"#,
        #"{"providers":{"anthropic":{"api":"openai-completions","baseUrl":"https://a/v1","models":[{"id":"m"}]}}}"#
    ])
    func `an entry ask cannot honour is an error, not a guess`(json: String) {
        #expect(throws: ProviderSettingsError.self) { try resolve(json, provider: "x") }
    }

    @Test func `a file that is not valid settings is an error`() {
        #expect(throws: ProviderSettingsError.self) { try settings("{ not json") }
    }

    @Test func `a missing file is no settings, not an error`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "ask-no-such-\(UUID()).json")
        #expect(try ProviderSettings.load(from: missing.path) == .none)
    }
}
