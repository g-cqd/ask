/// What `ask skills` prints: the skills by name, with where each came from and what was noticed, then what lost a name, what was skipped, and the
/// directories searched. Plain lines, no colour, so it reads the same in a pipe.
public struct SkillReport: Sendable {
    public let catalog: SkillCatalog
    public let selection: SkillSelection
    public let verbose: Bool

    public init(catalog: SkillCatalog, selection: SkillSelection, verbose: Bool) {
        self.catalog = catalog
        self.selection = selection
        self.verbose = verbose
    }

    public var lines: [String] {
        var lines = [summary]
        for word in selection.unknown { lines.append("not a harness or a scope, so ignored: \(word)") }
        let width = catalog.skills.map(\.name.count).max() ?? 0
        for skill in catalog.byName {
            let label = "\(skill.source)/\(skill.scope.rawValue)"
            lines.append("  \(skill.name.padding(toWidth: width))  \(label.padding(toWidth: 18))  \(skill.file)")
            for note in skill.diagnostics { lines.append("      note: \(note)") }
            if verbose { lines += details(of: skill) }
        }
        if !catalog.shadowed.isEmpty {
            lines.append("name taken by an earlier skill, so not offered with it (name its source to reach it):")
            for skill in catalog.shadowed {
                lines.append("  \(skill.name)  \(skill.source)/\(skill.scope.rawValue)  \(skill.file)")
            }
        }
        if !catalog.skipped.isEmpty {
            lines.append("looked at and not a skill:")
            for item in catalog.skipped { lines.append("  \(item)") }
        }
        if verbose {
            lines.append("searched:")
            for root in catalog.roots {
                lines.append(
                    "  \(root.exists ? "found  " : "absent ") \(root.source)/\(root.scope.rawValue)  \(root.path)")
            }
        }
        return lines
    }

    private var summary: String {
        let count = catalog.skills.count
        let tokens = catalog.estimatedAdvertisementTokens
        return
            "\(count) skill\(count == 1 ? "" : "s") · \(catalog.shadowed.count) shadowed · \(catalog.skipped.count) skipped"
            + " · advertising them would cost about \(tokens) tokens a request (characters ÷ 4, an estimate)"
    }

    private func details(of skill: Skill) -> [String] {
        var lines: [String] = []
        if !skill.tools.isEmpty {
            let shown = skill.tools.map { $0.ask.map { "\($0)" } ?? "?\($0.token)" }.joined(separator: ", ")
            lines.append("      tools (shown, never honoured): \(shown)")
        }
        if !skill.disallowedTools.isEmpty {
            lines.append(
                "      disallowed tools (shown, never honoured): "
                    + skill.disallowedTools.map(\.token).joined(separator: ", "))
        }
        if skill.realFile != skill.file { lines.append("      is the file: \(skill.realFile)") }
        if !skill.models.tokens.isEmpty {
            lines.append("      models: \(skill.models.tokens.joined(separator: " > "))")
        }
        if !skill.otherKeys.isEmpty { lines.append("      other fields: \(skill.otherKeys.joined(separator: ", "))") }
        if !skill.modelInvocable {
            lines.append("      not offered to the model on its own (disable-model-invocation)")
        }
        return lines
    }
}

extension String {
    fileprivate func padding(toWidth width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
