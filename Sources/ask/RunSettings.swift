internal import AskAI
internal import AskAgentCore
internal import AskTUI

/// Everything one run takes from configuration, resolved together: the layers, and the model they name. A
/// reload produces a whole `RunSettings` or fails, so a half-edited file never leaves ask half-configured.
struct RunSettings: Equatable {
    var configuration: Configuration
    var model: ResolvedModel
    /// Configuration files that applied.
    var applied: [String]
    /// Notices from loading: an ignored project file, an ignored environment value.
    var notices: [String]

    var limits: RunLimits {
        RunLimits(
            maximumTurns: configuration.maxTurns.value,
            compactAtTokens: configuration.compactAt.value > 0 ? configuration.compactAt.value : nil)
    }

    /// Whether a run built for `other` would behave differently: its layers or its model changed.
    func differs(from other: RunSettings) -> Bool {
        configuration != other.configuration || model != other.model
    }

    /// What the screen is told when these settings replace `previous`: nothing when nothing changed; a heading
    /// and one line per changed setting when something did; a new label when the model did; and any notice that
    /// was not there before.
    func updates(replacing previous: RunSettings) -> [ConversationUpdate] {
        let lines: [String] = configuration.changes(from: previous.configuration)
        let fresh: [String] = notices.filter { !previous.notices.contains($0) }
        var updates: [ConversationUpdate] = []
        if differs(from: previous) { updates.append(.notice("Configuration reloaded.", isError: false)) }
        for line in lines { updates.append(.notice("  " + line, isError: false)) }
        for line in fresh { updates.append(.notice(line, isError: false)) }
        if model != previous.model { updates.append(.label(modelLabel(model))) }
        return updates
    }

    /// Lines for the user at startup: which configuration files apply, and what was ignored.
    var description: [String] {
        (applied.isEmpty ? [] : ["Configuration from " + applied.joined(separator: ", ") + "."]) + notices
    }
}
