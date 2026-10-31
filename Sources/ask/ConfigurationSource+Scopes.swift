internal import AskAI
internal import AskAgentCore

extension ConfigurationSource {
    /// ``ModelDiscovery/resolve`` within the project's `modelScopes` rule (roadmap 0094): a provider the person named that the rule does
    /// not allow is refused, and one a file, a resumed session or ask chose gives way to the rule's first provider, with its default
    /// model.
    func resolveWithinScope(
        _ configuration: Configuration, providers: ProviderSettings, provider: String?, model: String?,
        allowNetwork: Bool, choice: ModelDiscovery.Choice
    ) async throws -> (model: ResolvedModel, notices: [String], details: [String]) {
        var choice = choice
        choice.scope = ModelScopeGate.match(configuration, project: workspace, environment: environment)
        let discovered = try await ModelDiscovery.resolve(
            providers: providers, provider: provider, model: model, environment: environment,
            allowNetwork: allowNetwork, choice: choice)
        guard let scope = choice.scope else { return discovered }
        let serving = discovered.model.connection?.name ?? discovered.model.providerName
        switch scope.verdict(on: serving, named: choice.providerIsFlagged || choice.modelIsFlagged) {
            case .allowed: return discovered
            case .refused(let text): throw ModelScopeRefusal(description: text)
            case .replaced(let other, let text):
                choice.providerIsFlagged = true
                choice.modelIsFlagged = false
                let replaced = try await ModelDiscovery.resolve(
                    providers: providers, provider: other, model: nil, environment: environment,
                    allowNetwork: allowNetwork, choice: choice)
                return (replaced.model, replaced.notices, replaced.details + [text])
        }
    }
}
