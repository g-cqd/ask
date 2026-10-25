/// Why the provider settings cannot be honoured. Each case says what to change.
public enum ProviderSettingsError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The file is not valid settings.
    case unreadable(String)
    /// The file defines the built-in provider's name.
    case reservedName(String)
    /// No provider has this name.
    case unknownProvider(String, known: [String])
    /// The entry names a protocol ask does not speak.
    case unsupportedAPI(provider: String, api: String)
    /// Neither the command line nor the entry names a model.
    case noModel(provider: String)
    /// The entry's key names an environment variable that is not set.
    case missingVariable(provider: String, variable: String)
    /// A preset with a sign-in has no key from the environment or a sign-in.
    case notSignedIn(provider: String, variable: String?, login: String)
    /// The entry is no preset and lacks a field it needs.
    case incomplete(provider: String, field: String)
    /// The stored credentials could not be read, so a key that may be in them is unknown.
    case credentials(CredentialFileError)
    /// The endpoint may not be used (ADR-0024).
    case refusedEndpoint(provider: String, reason: String)
    /// The connection's aliases cannot be used for this request.
    case alias(ModelAliasError)

    public var description: String {
        switch self {
            // @dl:accept -- an enum describing each of its cases in a sentence: the three error enums share this shape, and the sentences are the data
            case .unreadable(let detail): "providers.json is not valid settings: \(detail)"
            case .reservedName(let name): "providers.json may not define \"\(name)\", which is built in"
            case .unknownProvider(let name, let known):
                "no provider is named \"\(name)\"; known: \(known.joined(separator: ", "))"
            case .unsupportedAPI(let provider, let api):
                "provider \"\(provider)\" uses api \"\(api)\"; only \"\(ProviderSettings.openAICompletions)\" and \"\(ProviderSettings.openAIResponses)\" are supported"
            // @dl:accept -- these enum-case sentences are independent diagnostic data, not shared logic with session-log repairs
            case .noModel(let provider) where provider == ProviderSettings.codex:
                "provider \"\(provider)\" has no model chosen: run `ask models codex` to list your account's, or pass --model"
            // @dl:accept -- these enum-case sentences are independent diagnostic data, not shared logic with session-log repairs
            case .noModel(let provider) where provider == ProviderSettings.agy:
                "provider \"\(provider)\" has no model chosen: run `ask models agy` to list your account's, then pass --model"
            case .noModel(let provider): "provider \"\(provider)\" lists no model; add one, or pass --model"
            case .missingVariable(let provider, let variable):
                "provider \"\(provider)\" reads its key from $\(variable), which is not set"
            case .notSignedIn(let provider, let variable, let login):
                "provider \"\(provider)\" has no key: run `ask login \(login)`"
                    + (variable.map { ", or set $\($0)" } ?? "")
            case .incomplete(let provider, let field):
                "provider \"\(provider)\" in providers.json needs \"\(field)\""
            case .credentials(let error): "the stored credentials cannot be used: \(error)"
            case .alias(let error): "model alias: \(error)"
            case .refusedEndpoint(let provider, let reason): "provider \"\(provider)\" was refused: \(reason)"
        }
    }
}
