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
        /// Every path that starts with this one, as text: `…/studio.aemi.sunset` names the `.dev` folder and the
        /// `.binarycookies` file beside it too, for an app whose data takes its identifier with several endings.
        case prefix
    }

    /// Canonical, as ``CanonicalPath/of(_:relativeTo:)`` makes it.
    public let path: String
    public let kind: Kind
    /// `path` in lower case, made once: a policy checks every path against each of its rules (PERF-04).
    let folded: String

    /// A rule for `path`, which must already be canonical.
    public init(_ path: String, _ kind: Kind) {
        self.path = path
        self.kind = kind
        folded = path.lowercased()
    }

    /// Whether `candidate`, a canonical path, is the rule's path, under it for a subpath, or starts with it for a prefix.
    public func matches(_ candidate: String) -> Bool { matches(folded: candidate.lowercased()) }

    /// ``matches(_:)`` for a candidate already in lower case, so a caller checking it against many rules lowers it once.
    func matches(folded other: String) -> Bool {
        let rule = folded
        switch kind {
            case .literal: return other == rule
            case .subpath: return other == rule || rule == "/" || other.hasPrefix(rule + "/")
            case .prefix: return other.hasPrefix(rule)
        }
    }

    /// What Seatbelt calls the kind.
    var seatbeltName: String {
        switch kind {
            case .literal: "literal"
            case .subpath: "subpath"
            case .prefix: "prefix"
        }
    }
}
