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
                        "Current model: \(resolved.label) (provider \(resolved.providerName), "
                            + "from \(settings.configuration.model.source))", isError: false))
            case .reset: await select(nil, announcing: "Model selection reset to configuration", update: update)
            case .choose(let provider, let model):
                let (named, id) = provider.map { ($0, model) } ?? serving(model)
                await select(
                    ModelSelection(provider: named, model: id), announcing: "Model selected for this run",
                    update: update)
        }
    }

    /// The provider and model for `/model WORD`: `provider/model` as written; else the provider whose list holds the model, for the effort in force
    /// (ADR-0118); else the provider in force now.
    private func serving(_ word: String) -> (provider: String, model: String) {
        let environment = LaunchEnvironment.values
        let (model, level) = current.withLock { ($0.settings.model, $0.settings.configuration.thinking.value) }
        let providers = (try? ProviderSettings.load(from: source.providersPath)) ?? .none
        let reference = ReferencedModel(
            word, providers: ModelQualifier.providerNames(providers, environment: environment))
        if let said = reference.provider { return (said, reference.model) }
        let found = ModelQualifier.infer(model: word, thinking: level, providers: providers, environment: environment)
        return (found ?? model.providerName, word)
    }

    /// Adopts `selection` only when the whole configuration, with it, resolves: a provider that is unknown, has no
    /// key, or is refused leaves the current model in force. Nothing is written to a file.
    ///
    /// A thinking level the new model does not take is put back to the provider's default, and said, rather than refusing the model; a model
    /// that takes levels then offers them (`/thinking`), so choosing a model and its effort is one movement.
    private func select(
        _ selection: ModelSelection?, announcing: String, update: @Sendable (ConversationUpdate) -> Void
    ) async {
        var candidate = source
        candidate.flags.selected = selection
        var resolved: RunSettings
        var notes: [String] = []
        do { resolved = try await candidate.load(allowNetwork: false) } catch let failure as ThinkingError {
            let was = candidate.flags.thinking.map(String.init(describing:)) ?? "the configured level"
            candidate.flags.thinking = .providerDefault
            do { resolved = try await candidate.load(allowNetwork: false) } catch {
                return refused(selection, error, update)
            }
            notes.append("Thinking went back to the provider's default: \(was) is not available here (\(failure)).")
        } catch { return refused(selection, error, update) }
        sourceState.withLock { $0 = candidate }
        await refreshSettings(update: update)
        update(.notice("\(announcing): \(selection?.model ?? resolved.model.label).", isError: false))
        for note in notes { update(.notice(note, isError: false)) }
        if selection != nil, await modelTakesThinking() { update(.fillDraft("/thinking ")) }
    }

    private func refused(
        _ selection: ModelSelection?, _ error: any Error, _ update: @Sendable (ConversationUpdate) -> Void
    ) {
        let what = selection.map { " (\($0.provider) \($0.model))" } ?? ""
        update(.notice("Model not changed\(what): \(error)", isError: true))
    }
}
