internal import AemiJSON
internal import Foundation

/// The providers a user configured in `providers.json`, beside the built-in Anthropic provider.
///
/// The shape is pi's `models.json` for the same purpose, so an entry carries over between the two:
///
/// ```json
/// { "default": "local",
///   "providers": { "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:8181/v1",
///                             "apiKey": "$LOCAL_KEY", "headers": {}, "models": [{ "id": "ornith-1.5-9b" }] } } }
/// ```
///
/// Only `openai-completions` and `openai-responses` are accepted: they are the protocols ask speaks besides
/// Anthropic's, which is built in under the reserved name `anthropic`. The known services are presets (``ProviderPreset``): an entry with a preset's
/// name gives only what it changes, so `{ "groq": { "defaultModel": "…" } }` is a whole entry. Keys come from a literal or from `$NAME` / `${NAME}`; a key that would run a
/// command, as pi allows with a leading `!`, is not supported.
public struct ProviderSettings: Sendable, Equatable {
    /// No configured providers: only the built-in one.
    public static let none = ProviderSettings(defaultProvider: nil, entries: [:])
    /// The model used with Anthropic when none is named.
    public static let anthropicDefaultModel = "claude-sonnet-5-5"
    /// The name of the built-in provider, which a file may not redefine.
    public static let anthropic = "anthropic"
    /// The ChatGPT subscription's Codex backend, also built in.
    public static let codex = "codex"
    /// The protocols a configured provider may name besides Anthropic's, which is built in.
    public static let openAICompletions = "openai-completions"
    public static let openAIResponses = "openai-responses"

    struct Entry: Decodable, Sendable, Equatable {
        struct Model: Decodable, Sendable, Equatable {
            let id: String
            let contextWindow: Int?
            let maxTokens: Int?
        }

        let api: String?
        let baseUrl: String?
        let apiKey: String?
        let headers: [String: String]?
        let models: [Model]?
        let defaultModel: String?

        /// An entry that changes nothing, which is how a preset no file mentions is resolved.
        init() {
            (api, baseUrl, apiKey, headers, models, defaultModel) = (nil, nil, nil, nil, nil, nil)
        }
    }

    private struct File: Decodable {
        let `default`: String?
        let providers: [String: Entry]?
    }

    let defaultProvider: String?
    let entries: [String: Entry]

    private init(defaultProvider: String?, entries: [String: Entry]) {
        self.defaultProvider = defaultProvider
        self.entries = entries
    }

    /// Settings decoded from a file's bytes.
    /// - Throws: ``ProviderSettingsError/unreadable(_:)`` when they are not settings.
    public init(decoding bytes: [UInt8]) throws(ProviderSettingsError) {
        do {
            let file = try AemiJSON.JSONDecoder().decode(File.self, from: bytes)
            self.init(defaultProvider: file.default, entries: file.providers ?? [:])
        } catch {
            throw .unreadable("\(error)")
        }
    }

    /// The settings at `path`; no settings when the file does not exist.
    public static func load(from path: String) throws(ProviderSettingsError) -> ProviderSettings {
        guard FileManager.default.fileExists(atPath: path) else { return .none }
        guard let data = FileManager.default.contents(atPath: path) else { throw .unreadable("cannot read \(path)") }
        return try ProviderSettings(decoding: Array(data))
    }

    /// The provider and model to use.
    /// - Parameters:
    ///   - provider: the name given on the command line, if any; else the file's default; else `anthropic`.
    ///   - model: the model given on the command line, if any; else the entry's default or first model.
    ///   - environment: where `$NAME` keys are read.
    ///   - storedKeys: reads the keys sign-ins stored, by provider name. Called only when nothing else gives a preset a
    ///     key, so a damaged credential file blocks only the providers that need it.
    /// - Returns: the provider, with its endpoint and key, and the model.
    /// - Throws: a ``ProviderSettingsError`` naming what cannot be honoured.
    public func resolve(
        provider: String?, model: String?, environment: [String: String],
        storedKeys: () throws(CredentialFileError) -> [String: String] = { [:] }
    ) throws(ProviderSettingsError) -> ResolvedModel {
        let name = provider ?? defaultProvider ?? Self.anthropic
        if let builtIn = try builtIn(name, model: model) { return builtIn }
        let preset = ProviderPreset.named(name)
        guard let entry = entries[name] ?? (preset != nil ? Entry() : nil) else {
            throw .unknownProvider(name, known: known(environment: environment, stored: (try? storedKeys()) ?? [:]))
        }
        let api = entry.api ?? (preset != nil ? Self.openAICompletions : nil)
        guard let api else { throw .incomplete(provider: name, field: "api") }
        guard api == Self.openAICompletions || api == Self.openAIResponses else {
            throw .unsupportedAPI(provider: name, api: api)
        }
        guard let baseURL = entry.baseUrl ?? preset?.address(environment: environment) else {
            throw .incomplete(provider: name, field: "baseUrl")
        }
        guard let chosen = model ?? entry.defaultModel ?? entry.models?.first?.id else {
            throw .noModel(provider: name)
        }
        let key = try credential(of: name, entry: entry, preset: preset, environment: environment, stored: storedKeys)
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed) else { throw .refusedEndpoint(provider: name, reason: "it is not a URL") }
        if let reason = EndpointPolicy.refusal(for: url, carriesCredential: key != nil) {
            throw .refusedEndpoint(provider: name, reason: reason)
        }
        let listed = entry.models?.first { $0.id == chosen }
        let headers = entry.headers ?? [:]
        return ResolvedModel(
            provider: api == Self.openAIResponses
                ? .openAIResponses(name: name, baseURL: url, apiKey: key, headers: headers)
                : .openAICompatible(name: name, baseURL: url, apiKey: key, headers: headers),
            model: chosen, contextWindow: listed?.contextWindow, maxOutputTokens: listed?.maxTokens)
    }

    /// The built-in provider called `name`, if there is one; nil for anything a file or a preset names.
    /// - Throws: ``ProviderSettingsError/reservedName(_:)`` when the file defines a built-in name, and
    ///   ``ProviderSettingsError/noModel(provider:)`` for a built-in provider that needs a model named.
    private func builtIn(_ name: String, model: String?) throws(ProviderSettingsError) -> ResolvedModel? {
        for reserved in [Self.anthropic, Self.codex] where entries[reserved] != nil { throw .reservedName(reserved) }
        switch name {
            case Self.anthropic: return ResolvedModel(provider: .anthropic, model: model ?? Self.anthropicDefaultModel)
            case Self.codex:
                guard let model else { throw .noModel(provider: name) }
                return ResolvedModel(provider: .codex, model: model)
            default: return nil
        }
    }

    /// The key to send: the entry's own, else the preset's variable, else the key a sign-in stored. A preset that
    /// has none is an error, never a request without a key. An entry that is no preset may have no key at all.
    private func credential(
        of name: String, entry: Entry, preset: ProviderPreset?, environment: [String: String],
        stored: () throws(CredentialFileError) -> [String: String]
    ) throws(ProviderSettingsError) -> String? {
        if let raw = entry.apiKey { return try Self.interpolate(raw, provider: name, environment: environment) }
        guard let preset else { return nil }
        if let variable = preset.keyVariable, let value = environment[variable], !value.isEmpty { return value }
        do {
            if let key = try stored()[name] { return key }
        } catch { throw .credentials(error) }
        if let login = preset.login { throw .notSignedIn(provider: name, variable: preset.keyVariable, login: login) }
        throw .missingVariable(provider: name, variable: preset.keyVariable ?? "")
    }

    /// Every provider name that resolves, in order; a preset with no key yet says what would give it one.
    private func known(environment: [String: String], stored: [String: String]) -> [String] {
        let presets = ProviderPreset.all.filter { entries[$0.name] == nil }
            .map { preset in
                let fromVariable = preset.keyVariable.map { !(environment[$0] ?? "").isEmpty } ?? false
                if fromVariable || stored[preset.name] != nil { return preset.name }
                let needs = [preset.keyVariable.map { "$" + $0 }, preset.login.map { "ask login " + $0 }]
                    .compactMap { $0 }
                return "\(preset.name) (needs \(needs.joined(separator: " or ")))"
            }
        return [Self.anthropic, Self.codex] + (entries.keys + presets).sorted()
    }

    /// `$NAME` or `${NAME}` from the environment, `$$…` as a literal `$…`, and anything else as written.
    private static func interpolate(_ raw: String, provider: String, environment: [String: String])
        throws(ProviderSettingsError) -> String
    {
        guard raw.hasPrefix("$") else { return raw }
        if raw.hasPrefix("$$") { return String(raw.dropFirst()) }
        var name = raw.dropFirst()
        if name.hasPrefix("{"), name.hasSuffix("}") { name = name.dropFirst().dropLast() }
        guard let value = environment[String(name)], !value.isEmpty else {
            throw .missingVariable(provider: provider, variable: String(name))
        }
        return value
    }
}
