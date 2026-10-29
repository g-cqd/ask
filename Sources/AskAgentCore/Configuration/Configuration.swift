public import AskAI

/// ask's effective settings, and where each came from.
///
/// Layers, lowest to highest: built-in defaults, the user's `config.json`, a trusted project's
/// `.ask/config.json`, `ASK_*` environment variables, command-line flags. A higher layer replaces a key it
/// sets and leaves the others alone (ADR-0030).
public struct Configuration: Sendable, Equatable {
    /// Where a setting's value came from.
    public enum Source: Sendable, Equatable, CustomStringConvertible {
        case defaults
        case file(String)
        case environment(String)
        case flag(String)
        /// A command the user ran in this process, such as `/model`; nothing was written to a file.
        case command(String)
        /// The strict sandbox a resumed session recorded (roadmap 0042).
        case session
        /// A connection's model alias, named `connection/alias`.
        case alias(String)

        public var description: String {
            switch self {
                case .defaults: "default"
                case .file(let path): path
                case .environment(let name): "$\(name)"
                case .flag(let name): "--\(name)"
                case .command(let name): "\(name) (this run)"
                case .session: "this session's record"
                case .alias(let name): "alias \(name)"
            }
        }
    }

    /// One setting's value and where it came from.
    public struct Setting<Value: Sendable & Equatable>: Sendable, Equatable {
        public var value: Value
        public var source: Source
    }

    public var model: Setting<String?>
    public var provider: Setting<String?>
    public var thinking: Setting<ThinkingLevel>
    public var maxTurns: Setting<Int>
    public var compactAt: Setting<CompactionThreshold>
    public var sandbox: Setting<SandboxSection>
    public var ui: Setting<UISection>
    public var skills: Setting<SkillsSection>
    public var mcp: Setting<MCPSection>
    public var environment: Setting<EnvironmentSection>
    /// What ask keeps awake while it works (roadmap 0090): the Mac, by default, so a long turn is not cut short by idle sleep.
    public var keepAwake = Setting(value: KeepAwakeMode.system, source: .defaults)
    /// Where keys and tokens are kept (roadmap 0110).
    public var credentials = Setting(value: CredentialStorage.auto, source: .defaults)
    /// Where each `ui` and `skills` key came from, by its dotted name; read through `source(ofKey:)`.
    var keySources: [String: Source] = [:]

    /// Built-in defaults only.
    public static let defaults = Configuration(
        model: Setting(value: nil, source: .defaults), provider: Setting(value: nil, source: .defaults),
        thinking: Setting(value: .providerDefault, source: .defaults),
        maxTurns: Setting(value: 100, source: .defaults),
        compactAt: Setting(value: .standard, source: .defaults),
        sandbox: Setting(value: SandboxSection(), source: .defaults),
        ui: Setting(value: UISection(), source: .defaults),
        skills: Setting(value: SkillsSection(), source: .defaults),
        mcp: Setting(value: MCPSection(), source: .defaults),
        environment: Setting(value: EnvironmentSection(), source: .defaults)
    )

    /// `self` with the single-valued keys `file` sets replaced; the sections are layered by ``applying(_:from:)``.
    private func applyingScalars(_ file: ConfigurationFile, from source: Source) -> Configuration {
        var next = self
        if let model = file.model { next.model = Setting(value: model, source: source) }
        if let provider = file.provider { next.provider = Setting(value: provider, source: source) }
        if let thinking = file.thinking { next.thinking = Setting(value: thinking, source: source) }
        if let turns = file.maxTurns { next.maxTurns = Setting(value: turns, source: source) }
        if let compactAt = file.compactAt { next.compactAt = Setting(value: compactAt, source: source) }
        if let keepAwake = file.keepAwake { next.keepAwake = Setting(value: keepAwake, source: source) }
        if let credentials = file.credentials { next.credentials = Setting(value: credentials, source: source) }
        return next
    }

    /// `self` with every key `file` sets replaced, attributed to `source`.
    public func applying(_ file: ConfigurationFile, from source: Source) -> Configuration {
        var next = recordingKeySources(of: file, from: source).applyingScalars(file, from: source)
        // @dl:accept -- heterogeneous per-key layering retains each section's type and origin; the table is the data
        if let section = file.sandbox {
            next.sandbox = Setting(value: next.sandbox.value.layered(with: section), source: source)
        }
        if let section = file.ui {
            next.ui = Setting(value: next.ui.value.layered(with: section), source: source)
        }
        if let section = file.skills {
            next.skills = Setting(value: next.skills.value.layered(with: section), source: source)
        }
        if let section = file.mcp { next.mcp = Setting(value: next.mcp.value.layered(with: section), source: source) }
        if let section = file.environment {
            next.environment = Setting(value: next.environment.value.layered(with: section), source: source)
        }
        return next
    }

    /// `self` with `ASK_MODEL`, `ASK_PROVIDER`, `ASK_THINKING`, `ASK_MAX_TURNS` and `ASK_COMPACT_AT` applied. A number that is
    /// not a whole number in range is ignored, and named in `problems`.
    public func applying(environment: [String: String], problems: inout [String]) -> Configuration {
        var next = self
        func text(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }
        func whole(_ name: String, atLeast minimum: Int) -> Int? {
            guard let value = text(name) else { return nil }
            guard let number = Int(value), number >= minimum else {
                problems.append("$\(name) is \"\(value)\"; it must be a whole number of at least \(minimum); ignored")
                return nil
            }
            return number
        }
        if let model = text("ASK_MODEL") { next.model = Setting(value: model, source: .environment("ASK_MODEL")) }
        if let provider = text("ASK_PROVIDER") {
            next.provider = Setting(value: provider, source: .environment("ASK_PROVIDER"))
        }
        func parsed<Value>(_ name: String, _ parse: (String) -> Value?, must: String) -> Setting<Value>? {
            guard let value = text(name) else { return nil }
            guard let parsed = parse(value) else {
                problems.append("$\(name) is \"\(value)\"; it must be \(must); ignored")
                return nil
            }
            return Setting(value: parsed, source: .environment(name))
        }
        if let thinking = parsed("ASK_THINKING", ThinkingLevel.init(rawValue:), must: "one of \(ThinkingLevel.choices)")
        {
            next.thinking = thinking
        }
        if text("ASK_MAX_TURNS") == "none" {
            next.maxTurns = Setting(value: Self.noTurnLimit, source: .environment("ASK_MAX_TURNS"))
        } else if let turns = whole("ASK_MAX_TURNS", atLeast: 1) {
            next.maxTurns = Setting(value: turns, source: .environment("ASK_MAX_TURNS"))
        }
        if let threshold = parsed(
            "ASK_COMPACT_AT", CompactionThreshold.init(parsing:), must: CompactionThreshold.expected)
        {
            next.compactAt = threshold
        }
        return next
    }

    /// `self` with the provider and model the user chose while ask was running. Both are replaced together: a
    /// model id means nothing without the provider that serves it.
    public func applying(selectedProvider provider: String, model: String, command: String) -> Configuration {
        var next = self
        next.provider = Setting(value: provider, source: .command(command))
        next.model = Setting(value: model, source: .command(command))
        return next
    }

    /// `self` narrowed by the strict sandbox a resumed session recorded, except for what a flag set: a flag is the
    /// user widening on purpose. The record only ever narrows; the source changes only when it did.
    public func applying(
        session record: SandboxSection, flaggedNetwork: Bool, flaggedWrite: Bool, flaggedRead: Bool
    ) -> Configuration {
        let narrowed = sandbox.value.layered(
            with: SandboxSection(
                write: flaggedWrite ? [] : record.write, read: flaggedRead ? [] : record.read,
                network: flaggedNetwork ? nil : record.network))
        guard narrowed != sandbox.value else { return self }
        var next = self
        next.sandbox = Setting(value: narrowed, source: .session)
        return next
    }

    /// `self` with the flags the user gave. A nil flag was not given. `network` and `write` replace what the files
    /// set rather than narrowing it: a flag is the user, and only the user widens the sandbox.
    public func applying(
        model: String?, provider: String?, maxTurns: Int?, compactAt: CompactionThreshold?,
        network: SandboxPolicy.Network? = nil,
        write: PathSetting? = nil, read: PathSetting? = nil, thinking: ThinkingLevel? = nil
    ) -> Configuration {
        var next = self
        if network != nil || write != nil || read != nil {
            var section = next.sandbox.value
            if let network { section.network = network }
            if let write { section.write = [write] }
            if let read { section.read = [read] }
            // @dl:accept -- a heterogeneous per-key layer table with distinct origins; erasing value types to build a runtime table would lose its checks
            next.sandbox = Setting(value: section, source: .flag("network/write/read"))
        }
        // @dl:accept -- one flag, one layer entry, with its own origin; the same table as above
        if let model { next.model = Setting(value: model, source: .flag("model")) }
        if let provider { next.provider = Setting(value: provider, source: .flag("provider")) }
        if let thinking { next.thinking = Setting(value: thinking, source: .flag("thinking")) }
        if let maxTurns { next.maxTurns = Setting(value: maxTurns, source: .flag("max-turns")) }
        if let compactAt { next.compactAt = Setting(value: compactAt, source: .flag("compact-at")) }
        return next
    }
}

extension Configuration {
    /// One line per setting that differs from `previous`, with its new value and where that came from: what a
    /// reload tells the user.
    public func changes(from previous: Configuration) -> [String] {
        var lines: [String] = []
        func compare<Value: Sendable & Equatable>(_ name: String, _ old: Setting<Value>, _ new: Setting<Value>) {
            guard old != new else { return }
            lines.append("\(name): \(Self.show(old.value)) → \(Self.show(new.value)) (\(new.source))")
        }
        // @dl:accept -- one compare per key: the change table is the data
        compare("model", previous.model, model)
        compare("provider", previous.provider, provider)
        compare("thinking", previous.thinking, thinking)
        compare("maxTurns", previous.maxTurns, maxTurns)
        compare("compactAt", previous.compactAt, compactAt)
        compare("keepAwake", previous.keepAwake, keepAwake)
        compare("credentials", previous.credentials, credentials)
        compare("sandbox", previous.sandbox, sandbox)
        compare("ui", previous.ui, ui)
        compare("skills", previous.skills, skills)
        compare("mcp", previous.mcp, mcp)
        compare("environment", previous.environment, environment)
        return lines
    }

    /// `maxTurns` with no limit (`"none"`, roadmap 0098): a count the loop never reaches.
    public static let noTurnLimit = Int.max

    /// The turn limit a run uses (roadmap 0098, owner's rule): a `maxTurns` set anywhere wins; unset, it is the default of 100 inside the
    /// sandbox and no limit outside it, where the person has already chosen to let the model act freely.
    public func turnLimit(sandboxed: Bool) -> Int {
        maxTurns.source != .defaults || sandboxed ? maxTurns.value : Self.noTurnLimit
    }

    /// A turn limit as written: a whole number of at least 1, or `none`. Nil for anything else.
    public static func turnLimit(parsing text: String) -> Int? {
        if text == "none" { return noTurnLimit }
        return Int(text).flatMap { $0 >= 1 ? $0 : nil }
    }

    /// A turn limit as a person writes it: `none` for no limit.
    public static func describeTurns(_ turns: Int) -> String { turns == noTurnLimit ? "none" : String(turns) }

    private static func show<Value>(_ value: Value) -> String {
        if let turns = value as? Int, turns == noTurnLimit { return "none" }
        if let text = value as? String { return "\"\(text)\"" }
        if let optional = value as? String?, optional == nil { return "default" }
        if let optional = value as? String? { return "\"\(optional ?? "")\"" }
        return "\(value)"
    }
}
