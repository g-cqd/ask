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
    /// The directory ask was started in, which a `workspace` write scope means.
    var workspace: String
    /// The concrete control and its evidence status; the configuration retains the separately requested level.
    var thinking: ThinkingControl? = nil
    var thinkingStatus = "provider defaults; no control sent"
    /// The control is looked up before the first request, because no descriptor was cached at load.
    var thinkingPending = false

    var limits: RunLimits {
        RunLimits(
            maximumTurns: configuration.maxTurns.value,
            compactAtTokens: configuration.compactAt.value > 0 ? configuration.compactAt.value : nil)
    }

    /// Whether a run built for `other` would behave differently: its layers or its model changed.
    func differs(from other: RunSettings) -> Bool {
        configuration != other.configuration || model != other.model || sandbox != other.sandbox
            || thinking != other.thinking || thinkingStatus != other.thinkingStatus
            || thinkingPending != other.thinkingPending
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
        if label != previous.label { updates.append(.label(label)) }
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
        var lines = [
            row("provider", c.provider.value ?? "(the default)", c.provider.source),
            row("model", c.model.value ?? "(the provider's default)", c.model.source),
            row("thinking", c.thinking.value.rawValue + " (\(thinkingStatus))", c.thinking.source),
            row("maxTurns", String(c.maxTurns.value), c.maxTurns.source),
            row("compactAt", String(c.compactAt.value), c.compactAt.source),
            "sandbox   " + (sandbox.isUnrestricted ? "off (--no-sandbox)" : "on")
                + (sandbox.isUnrestricted || c.sandbox.value.isEmpty
                    ? "" : ", \(c.sandbox.value)  [\(c.sandbox.source)]"),
            "          writes: \(writes), reads: \(reads), network: "
                + (sandbox.isUnrestricted ? "any" : sandbox.network.description)
        ]
        // Only when a file set something: the defaults are in ADR-0046.
        if !c.ui.value.isEmpty { lines.append(row("ui", c.ui.value.description, c.ui.source)) }
        lines.append("user file     \(userFile)  \(standing(userFile))")
        lines.append("project file  \(projectFile)  \(standing(projectFile))")
        return lines + notices.map { "note: \($0)" }
    }

    /// Lines for the user at startup: which configuration files apply, what was ignored, and a strict sandbox.
    var description: [String] {
        (applied.isEmpty ? [] : ["Configuration from " + applied.joined(separator: ", ") + "."]) + notices
            + (strictTag == nil ? [] : ["Sandbox: writes \(writes); reads \(reads); network \(sandbox.network)."])
            + (thinkingTag.map { ["\($0) (\(thinkingStatus))."] } ?? [])
    }

    /// Where the sandbox allows writing, in words.
    var writes: String {
        guard case .roots(let roots) = sandbox.write else { return "anywhere" }
        return (roots.isEmpty ? "nowhere" : "only under " + roots.joined(separator: ", "))
            + " and temporary directories"
    }

    /// Where the sandbox allows reading, in words.
    var reads: String {
        guard case .roots = sandbox.read else { return "anywhere but the protected paths" }
        return configuration.sandbox.value.read == [.workspace]
            ? "only the workspace, the system and developer tools"
            : "only under chosen paths, the system and developer tools"
    }

    /// What the status line shows at its left: the model, and the sandbox when it is not ask's default.
    var label: String { ([modelLabel(model)] + [thinkingTag, strictTag].compactMap { $0 }).joined(separator: " · ") }

    /// A short word for a sandbox that differs from the default, or nil: strict modes and `--no-sandbox` both show.
    var strictTag: String? {
        if sandbox.isUnrestricted { return "no sandbox" }
        var parts: [String] = []
        if case .roots(let roots) = sandbox.write {
            let canonicalWorkspace = CanonicalPath.of(workspace, relativeTo: "/") ?? workspace
            parts.append(roots == [canonicalWorkspace] ? "workspace only" : "writes limited")
        }
        if case .roots = sandbox.read {
            parts.append(configuration.sandbox.value.read == [.workspace] ? "reads workspace" : "reads limited")
        }
        if sandbox.network != .any { parts.append(sandbox.network == .none ? "no network" : "localhost only") }
        return parts.isEmpty ? nil : "sandbox: " + parts.joined(separator: ", ")
    }
}
