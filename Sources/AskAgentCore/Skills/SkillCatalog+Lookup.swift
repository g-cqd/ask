extension SkillCatalog {
    /// The skill called `name` among the ones `selection` allows, by precedence. A skill that lost its name to another is still found when the selection
    /// excludes the one that won (`from` naming its harness).
    ///
    /// Names compare without regard to case, and a name written with other punctuation (`Code Review`, `code_review`) finds `code-review`.
    public func find(_ name: String, selection: SkillSelection) -> SkillLookup {
        let pool = (skills + shadowed).filter { selection.includes(source: $0.source, scope: $0.scope) }
        let wanted = Self.normalized(name)
        if !wanted.isEmpty, let skill = pool.first(where: { Self.normalized($0.name) == wanted }) {
            return skill.modelInvocable ? .found(skill) : .onlyWhenAsked(skill)
        }
        let names = pool.filter(\.modelInvocable).map(\.name)
        let near = names.filter {
            Self.normalized($0).contains(wanted) || (!wanted.isEmpty && wanted.contains(Self.normalized($0)))
        }
        return .missing(suggestions: Array((near.isEmpty ? names : near).sorted().prefix(8)))
    }

    private static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
