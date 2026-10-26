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
    /// The name of the built-in Antigravity provider.
    public static let agy = "agy"
    /// Apple's on-device model, also built in: no sign-in, nothing to pay.
    public static let apple = "apple"
    /// The on-device model's id: the only one.
    public static let appleModel = "on-device"
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

    /// Destination names explicitly configured by the user, for registration collision checks.
    public var configuredNames: [String] { entries.keys.sorted() }

    /// The selected destination before model resolution.
    public func selectedProvider(_ override: String?) -> String { override ?? defaultProvider ?? Self.anthropic }

    /// Whether `providers.json` names a default provider.
    public var namesDefault: Bool { defaultProvider != nil }

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
    ///   - catalog: models discovered for the selected provider: Codex defaults and limits, or an OpenAI-compatible
    ///     provider's windows, which never choose a model and never outrank what an entry states. Never another provider's.
    ///   - connection: the selected named registration, already loaded from ask's user-only registry.
    ///   - aliases: that connection's local model names and default; ignored for anything but a named connection.
    ///   - storedKeys: reads the keys sign-ins stored, by provider name. Called only when nothing else gives a preset a
    ///     key, so a damaged credential file blocks only the providers that need it.
    /// - Returns: the provider, with its endpoint and key, and the model.
    /// - Throws: a ``ProviderSettingsError`` naming what cannot be honoured.
    public func resolve(
        provider: String?, model: String?, environment: [String: String], catalog: [CatalogModel] = [],
        connection: ConnectionRecord? = nil, aliases: ModelAliases = .empty,
        storedKeys: () throws(CredentialFileError) -> [String: String] = { [:] }
    ) throws(ProviderSettingsError) -> ResolvedModel {
        let name = selectedProvider(provider)
        if let connection {
            return try named(connection, name: name, model: model, catalog: catalog, aliases: aliases)
        }
        if let builtIn = try builtIn(name, model: model, catalog: catalog) { return builtIn }
        let target = try target(name, environment: environment, storedKeys: storedKeys)
        guard let chosen = model ?? target.entry.defaultModel ?? target.entry.models?.first?.id else {
            throw .noModel(provider: name)
        }
        let (url, key) = try endpoint(of: target, environment: environment, storedKeys: storedKeys)
        // What the user wrote beside the model wins; what they did not write is what the provider's list says.
        let stated = target.entry.models?.first { $0.id == chosen }
        let listed = catalog.first { $0.id == chosen }
        let headers = target.entry.headers ?? [:]
        return ResolvedModel(
            provider: target.api == Self.openAIResponses
                ? .openAIResponses(name: name, baseURL: url, apiKey: key, headers: headers)
                : .openAICompatible(name: name, baseURL: url, apiKey: key, headers: headers),
            model: chosen, contextWindow: stated?.contextWindow ?? listed?.contextWindow,
            maxOutputTokens: stated?.maxTokens ?? listed?.maxOutputTokens)
    }

    /// A registration must identify exactly the selected name and must not shadow configured or built-in authority.
    private func named(
        _ connection: ConnectionRecord, name: String, model: String?, catalog: [CatalogModel], aliases: ModelAliases
    )
        throws(ProviderSettingsError) -> ResolvedModel
    {
        guard name.lowercased() == connection.name, !connection.removed,
            !configuredNames.contains(where: { $0.lowercased() == connection.name }),
            ProviderPreset.named(connection.name) == nil,
            ![Self.anthropic, Self.codex, Self.agy, Self.apple, "claude"].contains(connection.name)
        else { throw .reservedName(name) }
        let choice: ModelChoice?
        do { choice = try aliases.choice(requested: model, catalog: catalog) } catch { throw .alias(error) }
        guard var resolved = try builtIn(connection.provider.rawValue, model: choice?.model ?? model, catalog: catalog)
        else { throw .unknownProvider(name, known: []) }
        resolved.connection = connection
        resolved.alias = choice?.alias
        resolved.thinking = choice?.thinking
        // What the user stated about an alias is theirs and wins; what they did not state is still the server's.
        resolved.contextWindow = choice?.contextWindow ?? resolved.contextWindow
        resolved.maxOutputTokens = choice?.maxOutputTokens ?? resolved.maxOutputTokens
        return resolved
    }

    /// The built-in provider called `name`, if there is one; nil for anything a file or a preset names.
    /// - Throws: ``ProviderSettingsError/reservedName(_:)`` when the file defines a built-in name, and
    ///   ``ProviderSettingsError/noModel(provider:)`` for a built-in provider that needs a model named.
    private func builtIn(_ name: String, model: String?, catalog: [CatalogModel]) throws(ProviderSettingsError)
        -> ResolvedModel?
    {
        for reserved in [Self.anthropic, Self.codex, Self.agy, Self.apple] where entries[reserved] != nil {
            throw .reservedName(reserved)
        }
        switch name {
            case Self.anthropic: return ResolvedModel(provider: .anthropic, model: model ?? Self.anthropicDefaultModel)
            case Self.codex:
                guard let chosen = model ?? catalog.first?.id else { throw .noModel(provider: name) }
                return Self.resolved(.codex, chosen, from: catalog)
            case Self.agy:
                guard let chosen = model else { throw .noModel(provider: name) }
                return Self.resolved(.agy, chosen, from: catalog)
            case Self.apple: return Self.resolved(.apple, model ?? Self.appleModel, from: catalog)
            default: return nil
        }
    }

    /// `chosen` on `provider`, with the limits the catalog states for it.
    private static func resolved(_ provider: ResolvedModel.Provider, _ chosen: String, from catalog: [CatalogModel])
        -> ResolvedModel
    {
        let listed = catalog.first { $0.id == chosen }
        return ResolvedModel(
            provider: provider, model: chosen, contextWindow: listed?.contextWindow,
            maxOutputTokens: listed?.maxOutputTokens)
    }

    /// The key to send: the entry's own, else the preset's variable, else the key a sign-in stored. A preset that
    /// has none is an error, never a request without a key. An entry that is no preset has the key stored under its name, or none.
    func credential(
        of name: String, entry: Entry, preset: ProviderPreset?, environment: [String: String],
        stored: () throws(CredentialFileError) -> [String: String]
    ) throws(ProviderSettingsError) -> String? {
        if let raw = entry.apiKey { return try Self.interpolate(raw, provider: name, environment: environment) }
        guard let preset else {
            // An endpoint with no key written beside it may have one stored by `ask login custom`; else it needs none. A file that cannot be
            // read gives none rather than an error, so a damaged one blocks only the providers that need a key, as it always did.
            return (try? stored())?[name]
        }
        if let variable = preset.keyVariable, let value = environment[variable], !value.isEmpty { return value }
        do {
            if let key = try stored()[name] { return key }
        } catch { throw .credentials(error) }
        if let login = preset.login { throw .notSignedIn(provider: name, variable: preset.keyVariable, login: login) }
        throw .missingVariable(provider: name, variable: preset.keyVariable ?? "")
    }

    /// Every provider name that resolves, in order; a preset with no key yet says what would give it one.
    func known(environment: [String: String], stored: [String: String]) -> [String] {
        let presets = ProviderPreset.all.filter { entries[$0.name] == nil }
            .map { preset in
                let fromVariable = preset.keyVariable.map { !(environment[$0] ?? "").isEmpty } ?? false
                if fromVariable || stored[preset.name] != nil { return preset.name }
                let needs = [preset.keyVariable.map { "$" + $0 }, preset.login.map { "ask login " + $0 }]
                    .compactMap { $0 }
                return "\(preset.name) (needs \(needs.joined(separator: " or ")))"
            }
        return [Self.anthropic, Self.codex, Self.agy, Self.apple] + (entries.keys + presets).sorted()
    }

    /// `$NAME` or `${NAME}` from the environment, `$$…` as a literal `$…`, and anything else as written.
    private static func interpolate(_ raw: String, provider: String, environment: [String: String])
        throws(ProviderSettingsError) -> String
    {
        if raw.hasPrefix("$$") { return String(raw.dropFirst()) }
        guard let name = Self.variableName(in: raw) else { return raw }
        guard let value = environment[name], !value.isEmpty else {
            throw .missingVariable(provider: provider, variable: name)
        }
        return value
    }

    /// The variable a key names as `$NAME` or `${NAME}`; nil for a literal key, and for the `$$` that escapes a dollar.
    static func variableName(in raw: String) -> String? {
        guard raw.hasPrefix("$"), !raw.hasPrefix("$$") else { return nil }
        var name = raw.dropFirst()
        if name.hasPrefix("{"), name.hasSuffix("}") { name = name.dropFirst().dropLast() }
        return String(name)
    }

    /// The variables the configured providers read their keys from: what ask itself reads, and a command must not inherit (ADR-0106).
    var referencedVariables: Set<String> {
        Set(entries.values.compactMap { $0.apiKey.flatMap(Self.variableName(in:)) }.filter { !$0.isEmpty })
    }
}
