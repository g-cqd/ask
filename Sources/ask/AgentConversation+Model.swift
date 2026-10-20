internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// What `/model` was asked.
    enum ModelRequest: Equatable {
        case show
        case reset
        /// `provider` is nil for `/model MODEL`: the provider in force now.
        case choose(provider: String?, model: String)
    }

    /// Reads `/model`'s arguments. A model id may contain slashes and colons, so words are only split on spaces.
    static func parseModel(_ arguments: String) -> ModelRequest? {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.count {
            case 0: return .show
            case 1 where words[0] == "--reset": return .reset
            case 1 where !words[0].hasPrefix("--"): return .choose(provider: nil, model: words[0])
            case 2 where !words[0].hasPrefix("--") && !words[1].hasPrefix("--"):
                return .choose(provider: words[0], model: words[1])
            default: return nil
        }
    }

    /// `/model`: shows the model, chooses one for this run, or goes back to what the configuration says.
    func model(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard let request = Self.parseModel(arguments) else {
            update(.notice("Usage: /model [PROVIDER] MODEL, or /model --reset.", isError: true))
            return
        }
        switch request {
            case .show:
                let settings = current.withLock { $0.settings }
                let resolved = settings.model
                update(
                    .notice(
                        "Current model: \(modelLabel(resolved)) (provider \(resolved.providerName), "
                            + "from \(settings.configuration.model.source))", isError: false))
            case .reset: await select(nil, announcing: "Model selection reset to configuration", update: update)
            case .choose(let provider, let model):
                let named = provider ?? current.withLock { $0.settings.model.providerName }
                await select(
                    ModelSelection(provider: named, model: model), announcing: "Model selected for this run",
                    update: update)
        }
    }

    /// Adopts `selection` only when the whole configuration, with it, resolves: a provider that is unknown, has no
    /// key, or is refused leaves the current model in force. Nothing is written to a file.
    private func select(
        _ selection: ModelSelection?, announcing: String, update: @Sendable (ConversationUpdate) -> Void
    ) async {
        var candidate = source
        candidate.flags.selected = selection
        let resolved: RunSettings
        do { resolved = try await candidate.load(allowNetwork: false) } catch {
            let what = selection.map { " (\($0.provider) \($0.model))" } ?? ""
            update(.notice("Model not changed\(what): \(error)", isError: true))
            return
        }
        sourceState.withLock { $0 = candidate }
        await refreshSettings(update: update)
        update(.notice("\(announcing): \(selection?.model ?? modelLabel(resolved.model)).", isError: false))
    }
}
