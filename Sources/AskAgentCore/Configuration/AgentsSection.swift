/// The `agents` section of a configuration file (roadmap 0063, ADR-0146): whether the model may start subagents, whether they may write,
/// and how many turns each may take. Off unless the person's own file turns it on; a project's may turn it off, never on.
public struct AgentsSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `agents.enabled`: whether the model has the `agent` tool.
    public var enabled: Bool?
    /// `agents.allowWrites`: whether a subagent may change files; read-only otherwise.
    public var allowWrites: Bool?
    /// `agents.maxTurns`: the most turns one subagent may take.
    public var maxTurns: Int?
    /// `agents.otherHarnesses`: whether Claude's, Codex's and Copilot's agent definitions are read too (the owner: behind a setting).
    public var otherHarnesses: Bool?
    /// `agents.resolveWithModel`: whether a cheap model classifies the model words a definition uses that no listed id matches.
    public var resolveWithModel: Bool?

    public static let defaultTurns = 30
    static let mostTurns = 200

    public init() {}

    /// The keys, in the order they are shown, from their declarations (``AgentsSection/settings``).
    public static let keys = settings.all.map(\.name)

    public var isEnabled: Bool { enabled ?? false }
    public var writes: Bool { allowWrites ?? false }
    public var turns: Int { maxTurns ?? Self.defaultTurns }
    public var readsOtherHarnesses: Bool { otherHarnesses ?? false }
    public var resolvesWithModel: Bool { resolveWithModel ?? true }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public var description: String { Self.settings.describe(self) }
}
