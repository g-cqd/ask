internal import Foundation
internal import Testing

@testable import AskAI

/// The OpenAI-compatible services ask knows by name, so `--provider groq` needs only `GROQ_API_KEY` (roadmap 0034).
///
/// Every preset's endpoint answered a keyless request as an API wanting a key (diary 18); the names and variables are
/// pi's, so one environment serves both tools.
@Suite("Built-in presets reach the known OpenAI-compatible services from a key alone")
struct ProviderPresetTests {
    private func resolve(
        _ json: String? = nil, provider: String, model: String? = "m", environment: [String: String] = [:]
    ) throws -> ResolvedModel {
        let settings = try json.map { (text) throws in try ProviderSettings(decoding: Array(text.utf8)) } ?? .none
        return try settings.resolve(provider: provider, model: model, environment: environment)
    }

    @Test func `a preset resolves with no providers.json, from its key variable`() throws {
        let resolved = try resolve(provider: "groq", environment: ["GROQ_API_KEY": "gsk-1"])
        #expect(
            resolved.provider
                == .openAICompatible(
                    name: "groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: "gsk-1",
                    headers: [:]))
        #expect(resolved.model == "m")
    }

    @Test func `a preset whose variable is unset is refused, never sent without a key`() {
        #expect(throws: ProviderSettingsError.missingVariable(provider: "groq", variable: "GROQ_API_KEY")) {
            try resolve(provider: "groq")
        }
    }

    @Test func `a preset with no model named says how to name one`() {
        #expect(throws: ProviderSettingsError.noModel(provider: "groq")) {
            try resolve(provider: "groq", model: nil, environment: ["GROQ_API_KEY": "k"])
        }
    }

    @Test func `an entry with a preset's name need give only what it changes`() throws {
        let json = #"{ "default": "groq", "providers": { "groq": { "defaultModel": "llama" } } }"#
        let resolved = try ProviderSettings(decoding: Array(json.utf8))
            .resolve(provider: nil, model: nil, environment: ["GROQ_API_KEY": "k"])
        #expect(resolved.model == "llama")
        guard case .openAICompatible(_, let url, let key, _) = resolved.provider else {
            Issue.record("not the preset")
            return
        }
        #expect(url.absoluteString == "https://api.groq.com/openai/v1")
        #expect(key == "k")
    }

    @Test func `an entry with a preset's name overrides the endpoint and key it gives`() throws {
        let json = #"{ "providers": { "groq": { "baseUrl": "https://proxy.example/v1", "apiKey": "$PROXY" } } }"#
        let resolved = try resolve(json, provider: "groq", environment: ["PROXY": "p"])
        guard case .openAICompatible(_, let url, let key, _) = resolved.provider else {
            Issue.record("not the override")
            return
        }
        #expect(url.absoluteString == "https://proxy.example/v1")
        #expect(key == "p")
    }

    @Test func `an entry that is no preset must still say where to connect`() {
        #expect(throws: ProviderSettingsError.incomplete(provider: "mine", field: "baseUrl")) {
            try resolve(#"{ "providers": { "mine": { "api": "openai-completions" } } }"#, provider: "mine")
        }
    }

    @Test func `an unknown name lists the presets, marking those whose key is unset`() throws {
        do {
            _ = try resolve(provider: "nope", environment: ["GROQ_API_KEY": "k"])
            Issue.record("an unknown provider resolved")
        } catch let error as ProviderSettingsError {
            let text = "\(error)"
            #expect(text.contains("groq,") || text.hasSuffix("groq"))
            #expect(text.contains("openrouter (needs $OPENROUTER_API_KEY)"))
        }
    }

    @Test func `every preset is https, uniquely named, and reads a variable`() {
        let names = ProviderPreset.all.map(\.name)
        #expect(names.count >= 24, "the table lost entries")
        #expect(names == names.sorted())
        #expect(Set(names).count == names.count)
        #expect(!names.contains(ProviderSettings.anthropic))
        for preset in ProviderPreset.all {
            #expect(URL(string: preset.baseURL)?.scheme == "https", "\(preset.name)")
            #expect(!preset.baseURL.hasSuffix("/"), "\(preset.name)")
            #expect(!preset.keyVariable.isEmpty, "\(preset.name)")
        }
    }
}
