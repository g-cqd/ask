/// What a run may touch: the network, where it may write, and the paths it may neither read nor write (ADR-0035).
///
/// Policies narrow and never widen. The effective policy for a call is the intersection of the layers it sits in,
/// and only the user, by flag or configuration, ever makes one wider. Reading is a deny list for now; an allow
/// list needs a deny-default Seatbelt base and arrives with the strict modes.
public struct SandboxPolicy: Sendable, Equatable {
    /// How far the network reaches, from nowhere to anywhere. Ordered, so the narrower of two is the lesser.
    public enum Network: Int, Sendable, Equatable, Comparable {
        case none, localhost, any

        public static func < (left: Network, right: Network) -> Bool { left.rawValue < right.rawValue }
    }

    public var network: Network
    public var write: PathScope
    /// Paths that may not be read. Everything here is also unwritable: a path that cannot be read but could be
    /// moved away, or replaced, protects nothing.
    public private(set) var denyRead: [SandboxRule]
    /// Paths that may not be written, renamed or removed.
    public private(set) var denyWrite: [SandboxRule]

    /// A policy. `denyRead` is added to `denyWrite`.
    public init(
        network: Network = .any, write: PathScope = .anywhere, denyRead: [SandboxRule] = [],
        denyWrite: [SandboxRule] = []
    ) {
        self.network = network
        self.write = write
        self.denyRead = denyRead
        self.denyWrite = denyWrite + denyRead.filter { !denyWrite.contains($0) }
    }

    /// Nothing is restricted. For tests, and for a run the user asked to be unsandboxed.
    public static let unrestricted = SandboxPolicy()

    /// Whether the policy restricts anything at all.
    public var isUnrestricted: Bool { self == .unrestricted }

    /// What both policies allow, and nothing more.
    public func intersecting(_ other: SandboxPolicy) -> SandboxPolicy {
        SandboxPolicy(
            network: Swift.min(network, other.network), write: write.intersecting(other.write),
            denyRead: Self.union(denyRead, other.denyRead), denyWrite: Self.union(denyWrite, other.denyWrite))
    }

    private static func union(_ left: [SandboxRule], _ right: [SandboxRule]) -> [SandboxRule] {
        left + right.filter { !left.contains($0) }
    }

    /// Whether `capability` may touch `path`: canonicalized first, relative to `directory`.
    ///
    /// A path that cannot be resolved is refused: not knowing where it leads is not a reason to allow it.
    public func authorize(_ capability: SandboxCapability, path: String, relativeTo directory: String)
        -> SandboxDecision
    {
        guard let canonical = CanonicalPath.of(path, relativeTo: directory) else {
            return .denied(capability, "\(path) cannot be resolved to a real location, so it is not allowed.")
        }
        switch capability {
            case .read:
                return Self.refusal(.read, by: denyRead, for: canonical, verb: "read") ?? .allowed
            case .write:
                if let refused = Self.refusal(.write, by: denyWrite, for: canonical, verb: "written") { return refused }
                return write.contains(canonical)
                    ? .allowed : .denied(.write, "\(canonical) is outside the places this run may write.")
            case .network:
                return .allowed
        }
    }

    /// The refusal for `canonical` when one of `rules` covers it, naming the rule.
    private static func refusal(
        _ capability: SandboxCapability, by rules: [SandboxRule], for canonical: String, verb: String
    ) -> SandboxDecision? {
        rules.first { $0.matches(canonical) }
            .map {
                .denied(capability, "\(canonical) is protected: \(describe($0)) cannot be \(verb).")
            }
    }

    /// `rule`, as a sentence fragment: `/Users/g/.aws and everything under it`, or `/Users/g/.ssh/id_rsa`.
    static func describe(_ rule: SandboxRule) -> String {
        rule.kind == .subpath ? "\(rule.path) and everything under it" : rule.path
    }
}

extension SandboxPolicy {
    /// Every directory above a protected path, nearest the root last: the ones a rename could carry a protected
    /// path away inside (see ``SeatbeltProfile``). Not `/` itself, which no one renames.
    public var guardedAncestors: [String] {
        var seen = Set<String>()
        var ancestors: [String] = []
        for rule in denyWrite {
            var parts = rule.path.split(separator: "/").map(String.init)
            parts.removeLast()
            while !parts.isEmpty {
                let ancestor = "/" + parts.joined(separator: "/")
                if seen.insert(ancestor.lowercased()).inserted { ancestors.append(ancestor) }
                parts.removeLast()
            }
        }
        return ancestors
    }
}
