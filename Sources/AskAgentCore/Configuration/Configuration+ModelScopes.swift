extension Configuration {
    /// The first `modelScopes` rule the repository matches, or nil when none does and every provider may serve
    /// (roadmap 0094).
    public func modelScope(for facts: RepositoryFacts) -> ModelScopeMatch? {
        modelScopes.value.enumerated().first { $0.element.matches(facts) }
            .map { ModelScopeMatch(number: $0.offset + 1, scope: $0.element) }
    }
}
