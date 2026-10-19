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

        public var description: String {
            switch self {
                case .defaults: "default"
                case .file(let path): path
                case .environment(let name): "$\(name)"
                case .flag(let name): "--\(name)"
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
    public var maxTurns: Setting<Int>
    public var compactAt: Setting<Int>
    public var sandbox: Setting<SandboxSection>

    /// Built-in defaults only.
    public static let defaults = Configuration(
        model: Setting(value: nil, source: .defaults), provider: Setting(value: nil, source: .defaults),
        maxTurns: Setting(value: 100, source: .defaults),
        compactAt: Setting(value: AgentSettings.defaultCompactAtTokens, source: .defaults),
        sandbox: Setting(value: SandboxSection(), source: .defaults))

    /// `self` with every key `file` sets replaced, attributed to `source`.
    public func applying(_ file: ConfigurationFile, from source: Source) -> Configuration {
        var next = self
        if let model = file.model { next.model = Setting(value: model, source: source) }
        if let provider = file.provider { next.provider = Setting(value: provider, source: source) }
        if let turns = file.maxTurns { next.maxTurns = Setting(value: turns, source: source) }
        if let compactAt = file.compactAt { next.compactAt = Setting(value: compactAt, source: source) }
        if let section = file.sandbox {
            // What may be read is replaced by the file that names it (only the user's file can); what is kept
            // unreadable accumulates across layers, since every layer may narrow.
            let before = next.sandbox.value
            let merged = SandboxSection(
                allowRead: section.allowRead.isEmpty ? before.allowRead : section.allowRead,
                denyRead: before.denyRead + section.denyRead.filter { !before.denyRead.contains($0) })
            next.sandbox = Setting(value: merged, source: source)
        }
        return next
    }

    /// `self` with `ASK_MODEL`, `ASK_PROVIDER`, `ASK_MAX_TURNS` and `ASK_COMPACT_AT` applied. A number that is
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
        if let turns = whole("ASK_MAX_TURNS", atLeast: 1) {
            next.maxTurns = Setting(value: turns, source: .environment("ASK_MAX_TURNS"))
        }
        if let tokens = whole("ASK_COMPACT_AT", atLeast: 0) {
            next.compactAt = Setting(value: tokens, source: .environment("ASK_COMPACT_AT"))
        }
        return next
    }

    /// `self` with the flags the user gave. A nil flag was not given.
    public func applying(
        model: String?, provider: String?, maxTurns: Int?, compactAt: Int?
    ) -> Configuration {
        var next = self
        if let model { next.model = Setting(value: model, source: .flag("model")) }
        if let provider { next.provider = Setting(value: provider, source: .flag("provider")) }
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
        compare("model", previous.model, model)
        compare("provider", previous.provider, provider)
        compare("maxTurns", previous.maxTurns, maxTurns)
        compare("compactAt", previous.compactAt, compactAt)
        compare("sandbox", previous.sandbox, sandbox)
        return lines
    }

    private static func show<Value>(_ value: Value) -> String {
        if let text = value as? String { return "\"\(text)\"" }
        if let optional = value as? String?, optional == nil { return "default" }
        if let optional = value as? String? { return "\"\(optional ?? "")\"" }
        return "\(value)"
    }
}
