/// `policy`: what only an organisation decides (roadmap 0130, ADR-0168), set in its `requirements.json` and nowhere else. Every key is
/// optional; unset allows. Between the organisation's documents, a later one replaces what an earlier one set.
public struct PolicySection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `policy.allowNoSandbox`: whether `--no-sandbox` and `--yolo` may turn the sandbox off.
    public var allowNoSandbox: Bool?
    /// `policy.allowYes`: whether `--yes` and `--yolo` may run every tool call without asking.
    public var allowYes: Bool?
    /// `policy.providers`: the connections ask may use, by the name `/model` takes; `*` in a name matches anything.
    public var providers: [String]?
    /// `policy.models`: the models ask may use, by id; `*` in a name matches anything.
    public var models: [String]?

    /// The keys, in the order they are shown, from their declarations (``PolicySection/settings``).
    public static let keys = settings.all.map(\.name)

    public var description: String { Self.settings.describe(self) }

    /// What this policy does not allow of a run that turns the sandbox off (`noSandbox`), runs every call without asking (`yes`), and
    /// uses `model` on the connection `provider`; nil when it allows all of it.
    public func refusal(noSandbox: Bool, yes: Bool, provider: String, model: String) -> String? {
        if noSandbox, allowNoSandbox == false { return "turning the sandbox off (--no-sandbox, --yolo)" }
        if yes, allowYes == false { return "running every tool call without asking (--yes, --yolo)" }
        if !Self.allows(providers, provider) {
            return "the connection \(provider); it allows \(providers?.joined(separator: ", ") ?? "")"
        }
        if !Self.allows(models, model) {
            return "the model \(model); it allows \(models?.joined(separator: ", ") ?? "")"
        }
        return nil
    }

    /// Whether `name` is allowed by `list`: always when there is no list, else when one entry matches it, `*` matching any run of
    /// characters.
    public static func allows(_ list: [String]?, _ name: String) -> Bool {
        guard let list else { return true }
        return list.contains { matches($0[...], name[...]) }
    }

    private static func matches(_ pattern: Substring, _ name: Substring) -> Bool {
        guard let first = pattern.first else { return name.isEmpty }
        guard first == "*" else { return name.first == first && matches(pattern.dropFirst(), name.dropFirst()) }
        let rest = pattern.dropFirst()
        var tail = name
        while true {
            if matches(rest, tail) { return true }
            guard !tail.isEmpty else { return false }
            tail = tail.dropFirst()
        }
    }
}
