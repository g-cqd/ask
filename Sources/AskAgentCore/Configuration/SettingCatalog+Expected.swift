/// What each setting takes, in words, for a refusal (roadmap 0118): from its kind, or written out for a structured one.
extension SettingCatalog {
    /// The row for a dotted key (`ui.fold.tools`), if the catalog has one.
    static func setting(_ key: String) -> Setting? {
        all.first { $0.key == key }
    }

    /// The sections, which take an object.
    static let sections: Set<String> = ["sandbox", "ui", "ui.fold", "skills", "approvals", "environment", "mcp"]

    /// The structured settings' values, which their kind alone does not say.
    // @dl:disable near-clone -- a table of keys and their words: string literals that match other files' literals by shape only
    fileprivate static let structured: [String: String] = [
        "maxTurns": "a whole number of at least 1, or null for no limit",
        "compactAt": CompactionThreshold.expected,
        "sandbox.write": #""workspace", "anywhere" or a list of paths"#,
        "sandbox.read": #""workspace", "anywhere" or a list of paths"#,
        "sandbox.hide": "a list of paths", "sandbox.readable": "a list of paths", "sandbox.writable": "a list of paths",
        "approvals.allow": "a list of tool names", "approvals.ask": "a list of tool names",
        "skills.sources": "a list of harness names",
        "environment.withhold": "a list of variable names", "environment.pass": "a list of variable names",
        "ui.stopTwice": #"a list of "esc" and "ctrl-c""#
    ]
    // @dl:enable near-clone

    /// Words in quotes, the last joined with "or": `"a", "b" or "c"`.
    static func either(_ words: [String]) -> String {
        let quoted = words.map { "\"\($0)\"" }
        guard let last = quoted.last, quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " or " + last
    }
}

extension SettingCatalog.Setting {
    /// The dotted key, as a file and a message name it.
    var key: String { path.joined(separator: ".") }

    /// What the setting takes, in words: `true or false`, `"open" or "closed"`, `a whole number`.
    var expected: String {
        switch key {
            case "ui.timeoutLabel": return "1 to 8 characters, with no control characters"
            case "environment.shell": return "a shell's name, or an absolute path from /etc/shells"
            default: break
        }
        switch kind {
            case .boolean: return "true or false"
            case .choice(let words): return SettingCatalog.either(words)
            case .integer: return "a whole number"
            case .text: return "a string"
            case .structured: return SettingCatalog.structured[key] ?? ""
        }
    }
}
