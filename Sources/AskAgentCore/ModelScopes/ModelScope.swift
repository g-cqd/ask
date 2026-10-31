/// One `modelScopes` rule (roadmap 0094, ADR-0137): where it applies and the providers allowed there.
///
/// Each matcher it names must match; a rule names at least one. Patterns are ``ScopeGlob``s.
public struct ModelScope: Sendable, Equatable {
    /// The project's folder: this one and everything beneath it. `~` is the home folder.
    public var path: String?
    /// Any of the repository's remote URLs.
    public var remote: String?
    /// The address or the name the repository commits as.
    public var identity: String?
    /// The connections and providers allowed, by name.
    public var providers: [String]

    public init(path: String? = nil, remote: String? = nil, identity: String? = nil, providers: [String]) {
        self.path = path
        self.remote = remote
        self.identity = identity
        self.providers = providers
    }

    /// The matchers the rule names, as the file wrote them: what a refusal shows.
    var matchers: [(name: String, pattern: String)] {
        [("path", path), ("remote", remote), ("identity", identity)]
            .compactMap { name, pattern in
                pattern.map { (name, $0) }
            }
    }

    /// Whether the repository `facts` describe is one the rule is about.
    public func matches(_ facts: RepositoryFacts) -> Bool {
        if let path, !Self.covers(path, facts.project, home: facts.home) { return false }
        if let remote, !facts.remotes.contains(where: ScopeGlob(remote).matches) { return false }
        if let identity, !facts.identities.contains(where: ScopeGlob(identity).matches) { return false }
        return true
    }

    /// Whether `pattern` names `project` or a folder above it.
    private static func covers(_ pattern: String, _ project: String, home: String) -> Bool {
        var expanded = pattern
        if expanded == "~" || expanded.hasPrefix("~/") { expanded = home + expanded.dropFirst() }
        while expanded.count > 1, expanded.hasSuffix("/") { expanded.removeLast() }
        if ScopeGlob(expanded).matches(project) { return true }
        return ScopeGlob(expanded == "/" ? "/*" : expanded + "/*").matches(project)
    }
}
