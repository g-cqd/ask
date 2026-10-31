internal import AskAI
internal import Foundation

/// The accounts of one subscription that serve the same model (roadmap 0092): which subscription a `/model` name is, and which account
/// was last chosen for a model.
enum ModelAccounts {
    /// Where the choices are remembered: beside the configuration, never in it.
    static func memory(environment: [String: String] = LaunchEnvironment.values) -> ModelAccountMemory {
        ModelAccountMemory(url: URL(filePath: askConfigDirectory(environment: environment) + "/model-accounts.json"))
    }

    /// The subscription `name` reaches: Claude's or Codex's default sign-in, or a named connection; nil for anything else.
    static func kind(of name: String, connections: [ConnectionRecord]) -> ConnectionKind? {
        switch name {
            case ProviderSettings.anthropic: return .anthropic
            case ProviderSettings.codex: return .codex
            default: return connections.first { $0.name == name }?.provider
        }
    }

    /// The named connections, or none when they cannot be read.
    static func connections(environment: [String: String] = LaunchEnvironment.values) -> [ConnectionRecord] {
        (try? NamedConnections.registry(environment: environment).list().records) ?? []
    }

    /// Remembers `account` for `model` when it is one of a subscription's accounts; a choice that cannot be kept is not an error.
    static func remember(_ account: String, for model: String, environment: [String: String] = LaunchEnvironment.values)
    {
        guard let kind = kind(of: account, connections: connections(environment: environment)) else { return }
        try? memory(environment: environment).remember(account, for: model, kind: kind)
    }

    /// The account last chosen for `model`, when `provider` is one of a subscription's accounts and the remembered one is still there.
    static func remembered(
        for model: String, provider: String, environment: [String: String] = LaunchEnvironment.values
    )
        -> String?
    {
        let connections = connections(environment: environment)
        guard let kind = kind(of: provider, connections: connections),
            let account = memory(environment: environment).account(for: model, kind: kind),
            account == ProviderSettings.anthropic || account == ProviderSettings.codex
                || connections.contains(where: { $0.name == account })
        else { return nil }
        return account
    }
}
