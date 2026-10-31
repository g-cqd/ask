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
        compare("keepDisplayAwake", previous.keepDisplayAwake, keepDisplayAwake)
        compare("credentials", previous.credentials, credentials)
        compare("approvals", previous.approvals, approvals)
        compare("modelScopes", previous.modelScopes, modelScopes)
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

    /// A turn limit as a file takes it: `null` for no limit.
    public static func describeTurns(_ turns: Int) -> String { turns == noTurnLimit ? "null" : String(turns) }

    private static func show<Value>(_ value: Value) -> String {
        if let turns = value as? Int, turns == noTurnLimit { return "null" }
        if let text = value as? String { return "\"\(text)\"" }
        if let optional = value as? String?, optional == nil { return "default" }
        if let optional = value as? String? { return "\"\(optional ?? "")\"" }
        return "\(value)"
    }
}
