/// The `modelScopes` rule that decides for a repository, and its place in the list (roadmap 0094).
public struct ModelScopeMatch: Sendable, Equatable {
    /// Counted from 1, as a person reads the list.
    public let number: Int
    public let scope: ModelScope

    public init(number: Int, scope: ModelScope) {
        self.number = number
        self.scope = scope
    }

    /// Whether the connection or provider `name` may serve here; case is ignored.
    public func allows(_ name: String) -> Bool {
        scope.providers.contains { $0.lowercased() == name.lowercased() }
    }

    /// What the rule makes of `name` serving here; `named` is whether the person chose it for this run.
    public func verdict(on name: String, named: Bool) -> ModelScopeVerdict {
        if allows(name) { return .allowed }
        if named { return .refused(refusal(of: name)) }
        return .replaced(
            by: scope.providers[0],
            "modelScopes rule \(number) (\(rule)) does not allow \(name) here: using \(scope.providers[0]).")
    }

    /// The rule's matchers as the file wrote them: `path ~/work, identity *@acme.com`.
    private var rule: String { scope.matchers.map { "\($0.name) \($0.pattern)" }.joined(separator: ", ") }

    /// Why `name` is refused, with what is allowed instead.
    public func refusal(of name: String) -> String {
        "\(name) is not allowed here: modelScopes rule \(number) (\(rule)) allows only "
            + scope.providers.joined(separator: ", ") + ". Choose one of them with --provider or /model."
    }
}
