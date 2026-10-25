/// Which skills a request is about: the harnesses it names, and whether it means the user's, a project's or the bundled ones.
///
/// It is built from the words a person or a model writes (`["codex", "project"]`), cannot fail, and keeps the words it did not understand so they can
/// be reported. Narrowing is all it does: the empty selection is every harness's user and project skills, and no word makes it reach anything else.
public struct SkillSelection: Sendable, Equatable {
    /// The harnesses named, or nil for all of them.
    public let sources: Set<String>?
    /// The scopes wanted.
    public let scopes: Set<SkillScope>
    /// Words that were no harness and no scope.
    public let unknown: [String]

    /// Everything the user and their projects have, and nothing bundled.
    public static let standard = SkillSelection(tokens: [], knownSources: [])

    /// - Parameters:
    ///   - tokens: the words a person or a model wrote.
    ///   - knownSources: the harness ids that exist (the composition root's table), so a word can be told from a harness.
    public init(tokens: [String], knownSources: [String]) {
        let words = Set(tokens.map { $0.trimmingWhitespace().lowercased() }.filter { !$0.isEmpty })
        let named = words.intersection(knownSources)
        let scopeWords = words.intersection(["user", "project", SkillSource.bundledID])
        sources = named.isEmpty ? nil : named
        var wanted = Set<SkillScope>()
        if scopeWords.contains("user") { wanted.insert(.user) }
        if scopeWords.contains("project") { wanted.insert(.project) }
        if wanted.isEmpty { wanted = scopeWords == [SkillSource.bundledID] && named.isEmpty ? [] : [.user, .project] }
        if scopeWords.contains(SkillSource.bundledID) { wanted.insert(.bundled) }
        scopes = wanted
        let known = Set(knownSources).union(["user", "project", SkillSource.bundledID])
        unknown = tokens.map { $0.trimmingWhitespace() }.filter { !$0.isEmpty && !known.contains($0.lowercased()) }
    }

    func includes(source: String, scope: SkillScope) -> Bool {
        scopes.contains(scope) && (sources?.contains(source) ?? true)
    }
}
