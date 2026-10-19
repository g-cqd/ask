/// Where something is allowed to happen: everywhere, or only under some roots.
public enum PathScope: Sendable, Equatable {
    case anywhere
    /// Only at and under these canonical directories. No roots means nowhere.
    case roots([String])

    /// Whether `path`, canonical, is inside the scope.
    public func contains(_ path: String) -> Bool {
        switch self {
            case .anywhere: true
            case .roots(let roots): roots.contains { SandboxRule($0, .subpath).matches(path) }
        }
    }

    /// What both scopes allow, and nothing more: it only ever narrows.
    ///
    /// `anywhere` yields to the other scope. Two sets of roots keep, from each, the roots that lie inside some root
    /// of the other: a root inside a wider one is the narrower of the two, and unrelated roots drop out.
    public func intersecting(_ other: PathScope) -> PathScope {
        switch (self, other) {
            case (.anywhere, let scope), (let scope, .anywhere): return scope
            case (.roots(let mine), .roots(let theirs)):
                func inside(_ roots: [String], of others: [String]) -> [String] {
                    roots.filter { root in others.contains { SandboxRule($0, .subpath).matches(root) } }
                }
                var kept = inside(mine, of: theirs)
                for root in inside(theirs, of: mine)
                where !kept.contains(where: { $0.lowercased() == root.lowercased() }) {
                    kept.append(root)
                }
                return .roots(kept)
        }
    }
}
