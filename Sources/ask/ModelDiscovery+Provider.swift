internal import AskAI
internal import Foundation

extension ModelDiscovery {
    /// A damaged alias file refuses defaults, but not an explicitly named server model.
    static func connectionAliases(_ connection: ConnectionRecord?, model: String?, environment: [String: String]) throws
        -> (ModelAliases, [String])
    {
        guard let connection else { return (.empty, []) }
        do { return (try NamedConnections.aliases(for: connection, environment: environment).load(), []) } catch {
            guard model != nil else { throw error }
            return (.empty, ["Aliases not used: \(error)"])
        }
    }

    /// What the person said, apart from what the configuration says: whether the provider and the model came from a flag or a `/model`
    /// choice, and the thinking effort asked for.
    struct Choice {
        var providerIsFlagged = false
        var modelIsFlagged = false
        var thinking = ThinkingLevel.providerDefault
    }

    /// The provider and model once `provider/model` is read and, for a model no provider was named for, the provider that serves it is found
    /// (ADR-0118). A provider the person named on the command line is never overridden, a prefix equal to it is only dropped, and a model the
    /// configuration chose is not second-guessed.
    static func qualified(
        _ provider: String?, _ model: String?, providers: ProviderSettings, environment: [String: String],
        choice: Choice
    ) -> (provider: String?, model: String?, notices: [String]) {
        guard let model else { return (provider, nil, []) }
        let names = ModelQualifier.providerNames(providers, environment: environment)
        let reference = ReferencedModel(model, providers: names)
        if let said = reference.provider {
            if choice.providerIsFlagged, said != provider?.lowercased() { return (provider, model, []) }
            return (said, reference.model, [])
        }
        guard !choice.providerIsFlagged, choice.modelIsFlagged || provider == nil,
            let found = ModelQualifier.infer(
                model: model, thinking: choice.thinking, providers: providers, environment: environment),
            found != provider
        else { return (provider, model, []) }
        return (found, model, [detail("\(model) is served by \(found); \(found)/\(model) says so.")])
    }

    /// The provider to use when nothing named one (not a flag, the configuration or providers.json's default): one that can answer now. Said
    /// once, so a run never silently goes somewhere the person did not choose.
    static func automatic(
        _ provider: String?, providers: ProviderSettings, environment: [String: String]
    ) -> (provider: String?, notices: [String]) {
        guard provider == nil, !providers.namesDefault else { return (provider, []) }
        let picked = AutoProvider.pick(environment: environment)
        switch picked {
            case ProviderSettings.anthropic: return (picked, [])
            case ProviderSettings.apple:
                return (
                    picked, ["Nothing is signed in: using Apple's on-device model. /login signs in, /model switches."]
                )
            default:
                return (
                    picked,
                    [detail("No provider chosen; using \(picked), which you are signed in to. /model switches.")]
                )
        }
    }
}
