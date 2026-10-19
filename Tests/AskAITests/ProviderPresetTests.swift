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
        _ json: String? = nil, provider: String, model: String? = "m", environment: [String: String] = [:],
        stored: [String: String] = [:]
    ) throws -> ResolvedModel {
        let settings = try json.map { (text) throws in try ProviderSettings(decoding: Array(text.utf8)) } ?? .none
        return try settings.resolve(
            provider: provider, model: model, environment: environment, storedKeys: { stored })
    }

    private func damaged() throws(CredentialFileError) -> [String: String] {
        throw .damaged(path: "/p/credentials.json")
    }

    @Test func `a damaged credential file blocks only the providers that need a stored key`() throws {
        let settings = ProviderSettings.none
        let env = ["GROQ_API_KEY": "k"]
        // Never asked for: a key from the environment, a provider with no key, the built-in one.
        let groq = try settings.resolve(provider: "groq", model: "m", environment: env, storedKeys: damaged)
        #expect(endpoint(groq)?.key == "k")
        #expect(
            try settings.resolve(provider: "anthropic", model: nil, environment: [:], storedKeys: damaged).provider
                == .anthropic)
        let local =
            #"{ "providers": { "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:1/v1", "defaultModel": "m" } } }"#
        #expect(
            try ProviderSettings(decoding: Array(local.utf8))
                .resolve(provider: "local", model: nil, environment: [:], storedKeys: damaged).model == "m")
        // Asked for, and the damage is reported rather than read as "signed out".
        #expect(throws: ProviderSettingsError.credentials(.damaged(path: "/p/credentials.json"))) {
            try settings.resolve(provider: "spettro", model: "m", environment: [:], storedKeys: damaged)
        }
    }

    private func endpoint(_ resolved: ResolvedModel) -> (url: String, key: String?)? {
        guard case .openAICompatible(_, let url, let key, _) = resolved.provider else { return nil }
        return (url.absoluteString, key)
    }

    @Test func `a key a sign-in stored is used when no variable or entry gives one`() throws {
        let spettro = endpoint(try resolve(provider: "spettro", stored: ["spettro": "spk-1"]))
        #expect(spettro?.url == "https://api.spettro.app/v1")
        #expect(spettro?.key == "spk-1")
        #expect(endpoint(try resolve(provider: "mistral", stored: ["mistral": "mk-1"]))?.key == "mk-1")
    }

    @Test func `an environment variable beats a stored key, and an entry's key beats both`() throws {
        let env = ["MISTRAL_API_KEY": "from-env", "OTHER": "from-entry"]
        #expect(
            endpoint(try resolve(provider: "mistral", environment: env, stored: ["mistral": "stored"]))?.key
                == "from-env")
        let json = #"{ "providers": { "mistral": { "apiKey": "$OTHER" } } }"#
        #expect(
            endpoint(try resolve(json, provider: "mistral", environment: env, stored: ["mistral": "s"]))?.key
                == "from-entry")
    }

    @Test func `a preset with a sign-in and no key says how to sign in, and which variable also works`() {
        #expect(
            throws: ProviderSettingsError.notSignedIn(
                provider: "mistral", variable: "MISTRAL_API_KEY", login: "mistral-vibe")
        ) { try resolve(provider: "mistral") }
        #expect(throws: ProviderSettingsError.notSignedIn(provider: "spettro", variable: nil, login: "spettro")) {
            try resolve(provider: "spettro")
        }
        let text = ProviderSettingsError.notSignedIn(provider: "spettro", variable: nil, login: "spettro").description
        #expect(text.contains("ask login spettro"))
        #expect(!text.contains("$"))
    }

    @Test func `Spettro's address can be moved by its variable, but the key still needs https or this machine`() throws
    {
        let moved = try resolve(
            provider: "spettro", environment: ["SPETTRO_API_URL": "https://eu.spettro.example"],
            stored: ["spettro": "k"])
        #expect(endpoint(moved)?.url == "https://eu.spettro.example/v1")
        let local = try resolve(
            provider: "spettro", environment: ["SPETTRO_API_URL": "http://127.0.0.1:9000"], stored: ["spettro": "k"])
        #expect(endpoint(local)?.url == "http://127.0.0.1:9000/v1")
        #expect(throws: ProviderSettingsError.self) {
            try resolve(
                provider: "spettro", environment: ["SPETTRO_API_URL": "http://other.example"], stored: ["spettro": "k"])
        }
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
            #expect(text.contains("mistral (needs $MISTRAL_API_KEY or ask login mistral-vibe)"))
            #expect(text.contains("spettro (needs ask login spettro)"))
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
            #expect(preset.keyVariable != nil || preset.login != nil, "\(preset.name) has no way to be given a key")
        }
    }
}
