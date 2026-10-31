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
    /// What commands the model runs may inherit of ask's own environment (ADR-0106).
    var commandEnvironment = CommandEnvironment.inherit
    /// What ask did on its own account, not needed to read the conversation: shown with `--verbose` (ADR-0119).
    var details: [String] = []
    /// Whether `--verbose` was given.
    var verbose = false
    /// `--yes` or `--ask-always`, over the `approvals` section (roadmap 0134).
    var approvalFlag: ApprovalPolicy.Flag?
    /// `--allow` (roadmap 0156).
    var approvalAllow: [String] = []
    /// `--ask` other than `all` (roadmap 0154).
    var approvalAsk: [String] = []

    var limits: RunLimits {
        RunLimits(
            maximumTurns: configuration.turnLimit(sandboxed: !sandbox.isUnrestricted),
            compactAt: configuration.compactAt.value)
    }

    /// Whether a run built for `other` would behave differently: its layers or its model changed.
    func differs(from other: RunSettings) -> Bool {
        configuration != other.configuration || model != other.model || sandbox != other.sandbox
            || thinking != other.thinking || thinkingStatus != other.thinkingStatus
            || thinkingPending != other.thinkingPending || commandEnvironment != other.commandEnvironment
    }

    /// What the screen is told when these settings replace `previous`: nothing when nothing changed; a heading
    /// and one line per changed setting when something did; a new label when the model did; and any notice that
    /// was not there before.
    func updates(replacing previous: RunSettings) -> [ConversationUpdate] {
        let lines: [String] = configuration.changes(from: previous.configuration)
        let fresh: [String] = notices.filter { !previous.notices.contains($0) }
        var updates: [ConversationUpdate] = []
        if differs(from: previous) { updates.append(.detail("Configuration reloaded.")) }
        for line in lines { updates.append(.detail("  " + line)) }
        for line in fresh { updates.append(.notice(line, isError: false)) }
        for line in details where !previous.details.contains(line) { updates.append(.detail(line)) }
        if labelVariants != previous.labelVariants { updates.append(.labelVariants(labelVariants)) }
        if sandbox.isUnrestricted != previous.sandbox.isUnrestricted {
            updates.append(.sandboxActive(!sandbox.isUnrestricted))
        }
        return updates
    }

    /// The settings, one per line with where each came from, then the two files and what became of them: what
    /// `ask config` prints and `/config` shows.
    func report(userFile: String, projectFile: String) -> [String] {
        func row(_ name: String, _ value: String, _ source: Configuration.Source) -> String {
            name.padding(toLength: max(10, name.count + 1), withPad: " ", startingAt: 0) + "\(value)  [\(source)]"
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
            row(
                "maxTurns",
                Configuration.describeTurns(limits.maximumTurns)
                    + (c.maxTurns.source == .defaults
                        ? (sandbox.isUnrestricted ? " (no sandbox)" : " (sandbox on)") : ""),
                c.maxTurns.source),
            row("compactAt", Self.describe(c.compactAt.value), c.compactAt.source),
            row("keepAwake", c.keepAwake.value.rawValue, c.keepAwake.source),
            row("keepDisplayAwake", c.keepDisplayAwake.value ? "true" : "false", c.keepDisplayAwake.source),
            "sandbox   " + (sandbox.isUnrestricted ? "off (--no-sandbox)" : "on")
                + (sandbox.isUnrestricted || c.sandbox.value.isEmpty
                    ? "" : ", \(c.sandbox.value)  [\(c.sandbox.source)]"),
            "          writes: \(writes), reads: \(reads), network: "
                + (sandbox.isUnrestricted ? "any" : sandbox.network.description)
        ]
        lines += sectionRows
        lines.append(row("environment", commandEnvironmentSummary, c.environment.source))
        lines.append("user file     \(userFile)  \(standing(userFile))")
        lines.append("project file  \(projectFile)  \(standing(projectFile))")
        return lines + notices.map { "note: \($0)" }
    }

    /// What a command is not given of ask's environment, in words and never a value: ask's own and well-known credential variables and prefixes, then what is configured.
    var commandEnvironmentSummary: String {
        let policy = commandEnvironment
        let prefixes = policy.withheldPrefixes.map { $0 + "*" }.joined(separator: ", ")
        let configured = configuration.environment.value
        return "commands are not given \(policy.withheld.count) named variables and \(prefixes)"
            + (configured.isEmpty ? "" : "; configured: \(configured)")
    }

    /// What is said at startup whatever the verbosity: a file that was ignored, a catalog that could not be used, a provider chosen because nothing
    /// was signed in. Each is something the person may need to act on.
    var description: [String] { notices }

    /// What is said at startup only with `--verbose`: which files applied, the sandbox in force, the thinking effort, and what ask decided by itself.
    var detailLines: [String] {
        (applied.isEmpty ? [] : ["Configuration from " + applied.joined(separator: ", ") + "."]) + details
            + (strictTag == nil ? [] : ["Sandbox: writes \(writes); reads \(reads); network \(sandbox.network)."])
            + (thinkingTag.map { ["\($0) (\(thinkingStatus))."] } ?? [])
    }

    /// Where the sandbox allows writing, in words.
    var writes: String {
        guard case .roots(let all) = sandbox.write else { return "anywhere" }
        // The build caches are one phrase, not a path per home (they would push the conversation off a resumed screen).
        let caches = Set(SandboxPolicy.developerWrites(home: "").map { $0.lowercased() })
        let roots = all.filter { root in !caches.contains { root.lowercased().hasSuffix($0) } }
        let canonicalWorkspace = CanonicalPath.of(workspace, relativeTo: "/") ?? workspace
        let named = roots.map { $0 == canonicalWorkspace ? "the workspace" : $0 }
        return (roots.isEmpty ? "nowhere" : "only under " + named.joined(separator: ", "))
            + (roots.count == all.count ? "" : ", the build caches") + " and temporary directories"
    }

    /// Where the sandbox allows reading, in words.
    var reads: String {
        guard case .roots = sandbox.read else { return "anywhere but the protected paths" }
        return configuration.sandbox.value.read == [.workspace]
            ? "only the workspace, the system and developer tools"
            : "only under chosen paths, the system and developer tools"
    }

    /// What the status line shows at its left, longest first: `provider/model/effort`, then without the effort, then the model alone, so a
    /// narrow terminal gets a whole shorter label and not half of the long one. A warning mark leads when there is no sandbox; with `--verbose`
    /// a shield leads when there is one (roadmap 0074).
    var labelVariants: [String] {
        let provider = model.connection?.name ?? model.providerName
        let named = "\(provider)/\(model.model)"
        let effort = configuration.thinking.value
        var forms = effort == .providerDefault ? [] : ["\(named)/\(effort)"]
        forms += [named, model.model]
        let mark = verbose ? "⛨ " : ""
        var seen: Set<String> = []
        return forms.map { mark + $0 }.filter { seen.insert($0).inserted }
    }

    /// The longest form of the label.
    var label: String { labelVariants[0] }

    /// A short word for a sandbox that differs from the default, or nil: strict modes and `--no-sandbox` both show.
    var strictTag: String? {
        if sandbox.isUnrestricted { return "no sandbox" }
        var parts: [String] = []
        // The workspace is the default (owner, 2026-10-29): only a narrower or different write scope is strict.
        let chosen = configuration.sandbox.value.write
        if case .roots = sandbox.write, !chosen.isEmpty, chosen != [.workspace] { parts.append("writes limited") }
        if case .roots = sandbox.read {
            parts.append(configuration.sandbox.value.read == [.workspace] ? "reads workspace" : "reads limited")
        }
        switch sandbox.network {
            case .none: parts.append("no network")
            case .localhost: parts.append("localhost only")
            case .provider: parts.append("the providers only")
            case .any: break
        }
        return parts.isEmpty ? nil : "sandbox: " + parts.joined(separator: ", ")
    }

    /// Which tool calls ask before they run (roadmap 0134): the person's `approvals`, under the flag.
    var approvalPolicy: ApprovalPolicy {
        ApprovalPolicy(
            section: configuration.approvals.value, flag: approvalFlag, allowing: approvalAllow, asking: approvalAsk)
    }
}
