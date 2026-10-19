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
    /// The entry is no preset and lacks a field it needs.
    case incomplete(provider: String, field: String)
    /// The endpoint may not be used (ADR-0024).
    case refusedEndpoint(provider: String, reason: String)

    public var description: String {
        switch self {
            case .unreadable(let detail): "providers.json is not valid settings: \(detail)"
            case .reservedName(let name): "providers.json may not define \"\(name)\", which is built in"
            case .unknownProvider(let name, let known):
                "no provider is named \"\(name)\"; known: \(known.joined(separator: ", "))"
            case .unsupportedAPI(let provider, let api):
                "provider \"\(provider)\" uses api \"\(api)\"; only \"\(ProviderSettings.openAICompletions)\" is supported"
            case .noModel(let provider): "provider \"\(provider)\" lists no model; add one, or pass --model"
            case .missingVariable(let provider, let variable):
                "provider \"\(provider)\" reads its key from $\(variable), which is not set"
            case .incomplete(let provider, let field):
                "provider \"\(provider)\" in providers.json needs \"\(field)\""
            case .refusedEndpoint(let provider, let reason): "provider \"\(provider)\" was refused: \(reason)"
        }
    }
}
