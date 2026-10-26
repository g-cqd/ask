internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// `/thinking`: the effort the model is asked to think at, chosen from what the model's own list says it takes (ADR-0117).
extension AgentConversation {
    /// The rows for `/thinking `: the provider's own default, then each level the current model takes, the current one marked.
    func thinkingRows() async -> [ChoiceRow] {
        let (model, level) = current.withLock { ($0.settings.model, $0.settings.configuration.thinking.value) }
        let descriptor = await ThinkingDiscovery.descriptor(for: model, environment: LaunchEnvironment.values)
        guard let options = ThinkingOptions.choices(for: model.provider, descriptor: descriptor) else { return [] }
        var rows = [
            ChoiceRow(
                label: "default", detail: "what the provider does when nothing is asked", arguments: "default",
                isCurrent: level == .providerDefault)
        ]
        for option in options.levels {
            var notes: [String] = []
            if option == options.serverDefault { notes.append("the server's default") }
            if !options.verified { notes.append("unverified") }
            rows.append(
                ChoiceRow(
                    label: option.rawValue, detail: notes.joined(separator: " · "), arguments: option.rawValue,
                    isCurrent: level == option))
        }
        return rows
    }

    /// Whether the model now in force takes any thinking level, so a model choice can go on to ask for one.
    func modelTakesThinking() async -> Bool {
        let model = current.withLock { $0.settings.model }
        let descriptor = await ThinkingDiscovery.descriptor(for: model, environment: LaunchEnvironment.values)
        return ThinkingOptions.choices(for: model.provider, descriptor: descriptor).map { !$0.levels.isEmpty } ?? false
    }

    /// `/thinking [LEVEL]`: shows the level, or sets it for this run. Nothing is written to a file.
    func thinking(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        let word = arguments.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else {
            let settings = current.withLock { $0.settings }
            update(
                .notice(
                    "Thinking: \(settings.configuration.thinking.value) (\(settings.thinkingStatus)). /thinking LEVEL sets it; type /thinking to choose.",
                    isError: false))
            return
        }
        guard let level = ThinkingLevel(rawValue: word) else {
            update(.notice("Thinking not changed: \(word) is not one of \(ThinkingLevel.choices).", isError: true))
            return
        }
        var candidate = source
        candidate.flags.thinking = level
        do { _ = try await candidate.load(allowNetwork: false) } catch {
            update(.notice("Thinking not changed: \(error)", isError: true))
            return
        }
        sourceState.withLock { $0 = candidate }
        await refreshSettings(update: update)
        update(.notice("Thinking set to \(level) for this run.", isError: false))
    }
}
