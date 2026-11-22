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

    /// A rule for `path`, which must already be canonical.
    public init(_ path: String, _ kind: Kind) {
        self.path = path
        self.kind = kind
    }

    /// Whether `candidate`, a canonical path, is the rule's path, under it for a subpath, or starts with it for a prefix.
    public func matches(_ candidate: String) -> Bool {
        let rule = path.lowercased()
        let other = candidate.lowercased()
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
