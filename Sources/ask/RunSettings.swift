internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation

/// Everything one run takes from configuration, resolved together: the layers, and the model they name. A
/// reload produces a whole `RunSettings` or fails, so a half-edited file never leaves ask half-configured.
struct RunSettings: Equatable {
    var configuration: Configuration
    var model: ResolvedModel
    /// What the tools may touch: ask's protections, or nothing when the user turned them off.
    var sandbox: SandboxPolicy
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
        configuration != other.configuration || model != other.model || sandbox != other.sandbox
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

    /// The settings, one per line with where each came from, then the two files and what became of them: what
    /// `ask config` prints and `/config` shows.
    func report(userFile: String, projectFile: String) -> [String] {
        func row(_ name: String, _ value: String, _ source: Configuration.Source) -> String {
            name.padding(toLength: 10, withPad: " ", startingAt: 0) + "\(value)  [\(source)]"
        }
        func standing(_ path: String) -> String {
            if applied.contains(path) { return "(applied)" }
            return FileManager.default.fileExists(atPath: path) ? "(ignored)" : "(none)"
        }
        let c = configuration
        return [
            row("provider", c.provider.value ?? "(the default)", c.provider.source),
            row("model", c.model.value ?? "(the provider's default)", c.model.source),
            row("maxTurns", String(c.maxTurns.value), c.maxTurns.source),
            row("compactAt", String(c.compactAt.value), c.compactAt.source),
            "sandbox   " + (sandbox.isUnrestricted ? "off (--no-sandbox)" : "on"),
            "user file     \(userFile)  \(standing(userFile))",
            "project file  \(projectFile)  \(standing(projectFile))"
        ] + notices.map { "note: \($0)" }
    }

    /// Lines for the user at startup: which configuration files apply, and what was ignored.
    var description: [String] {
        (applied.isEmpty ? [] : ["Configuration from " + applied.joined(separator: ", ") + "."]) + notices
    }
}
