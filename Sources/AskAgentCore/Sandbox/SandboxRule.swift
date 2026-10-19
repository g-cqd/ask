/// One path a sandbox policy names: a file, or a directory with everything under it.
///
/// Matching is case-insensitive. The default volume is, so `~/.AWS/credentials` is `~/.aws/credentials` there and a
/// rule that missed it would be a hole; on a case-sensitive volume this only over-denies, which fails closed.
public struct SandboxRule: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        /// Exactly this path.
        case literal
        /// This path and everything beneath it.
        case subpath
    }

    /// Canonical, as ``CanonicalPath/of(_:relativeTo:)`` makes it.
    public let path: String
    public let kind: Kind

    /// A rule for `path`, which must already be canonical.
    public init(_ path: String, _ kind: Kind) {
        self.path = path
        self.kind = kind
    }

    /// Whether `candidate`, a canonical path, is the rule's path or under it, for a subpath.
    public func matches(_ candidate: String) -> Bool {
        let rule = path.lowercased()
        let other = candidate.lowercased()
        if other == rule { return true }
        guard kind == .subpath else { return false }
        return rule == "/" || other.hasPrefix(rule + "/")
    }
}
