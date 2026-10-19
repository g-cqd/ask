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
/// Only `openai-completions` is accepted: it is the one protocol ask speaks besides Anthropic's, which is built in
/// under the reserved name `anthropic`. Keys come from a literal or from `$NAME` / `${NAME}`; a key that would run a
/// command, as pi allows with a leading `!`, is not supported.
public struct ProviderSettings: Sendable, Equatable {
    /// No configured providers: only the built-in one.
    public static let none = ProviderSettings(defaultProvider: nil, entries: [:])
    /// The model used with Anthropic when none is named.
    public static let anthropicDefaultModel = "claude-sonnet-5-5"
    /// The name of the built-in provider, which a file may not redefine.
    public static let anthropic = "anthropic"
    /// The one protocol a configured provider may name.
    public static let openAICompletions = "openai-completions"

    struct Entry: Decodable, Sendable, Equatable {
        struct Model: Decodable, Sendable, Equatable { let id: String }

        let api: String
        let baseUrl: String
        let apiKey: String?
        let headers: [String: String]?
        let models: [Model]?
        let defaultModel: String?
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
    /// - Returns: the provider, with its endpoint and key, and the model.
    /// - Throws: a ``ProviderSettingsError`` naming what cannot be honoured.
    public func resolve(provider: String?, model: String?, environment: [String: String])
        throws(ProviderSettingsError) -> ResolvedModel
    {
        let name = provider ?? defaultProvider ?? Self.anthropic
        if entries[Self.anthropic] != nil { throw .reservedName(Self.anthropic) }
        if name == Self.anthropic {
            return ResolvedModel(provider: .anthropic, model: model ?? Self.anthropicDefaultModel)
        }
        guard let entry = entries[name] else {
            throw .unknownProvider(name, known: [Self.anthropic] + entries.keys.sorted())
        }
        guard entry.api == Self.openAICompletions else { throw .unsupportedAPI(provider: name, api: entry.api) }
        guard let chosen = model ?? entry.defaultModel ?? entry.models?.first?.id else {
            throw .noModel(provider: name)
        }
        let key = try entry.apiKey.map { (raw) throws(ProviderSettingsError) in
            try Self.interpolate(raw, provider: name, environment: environment)
        }
        let trimmed = entry.baseUrl.hasSuffix("/") ? String(entry.baseUrl.dropLast()) : entry.baseUrl
        guard let url = URL(string: trimmed) else { throw .refusedEndpoint(provider: name, reason: "it is not a URL") }
        if let reason = EndpointPolicy.refusal(for: url, carriesCredential: key != nil) {
            throw .refusedEndpoint(provider: name, reason: reason)
        }
        return ResolvedModel(
            provider: .openAICompatible(name: name, baseURL: url, apiKey: key, headers: entry.headers ?? [:]),
            model: chosen)
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
