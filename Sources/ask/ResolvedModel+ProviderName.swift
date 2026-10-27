internal import AskAI

extension ResolvedModel {
    /// The name a configuration or `/model` uses for this model's provider.
    var providerName: String {
        switch provider {
            case .anthropic: ProviderSettings.anthropic
            case .codex: ProviderSettings.codex
            case .agy: ProviderSettings.agy
            case .copilot: CopilotProtocol.name
            case .apple: ProviderSettings.apple
            case .openAICompatible(let name, _, _, _), .openAIResponses(let name, _, _, _): name
        }
    }
}
