/// The `skills` section of a configuration file (roadmap 0061). Every key is optional, and a layer that sets one replaces it.
public struct SkillsSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `skills.enabled`: whether skills are advertised and the `skill` tool offered at all. Off costs the model nothing: no block, no tool.
    public var enabled: Bool?
    /// `skills.maxListed`: how many skills the system prompt lists. The rest can still be loaded by name; the prompt says how many are not listed.
    public var maxAdvertised: Int?
    /// `skills.sources`: harness ids (and `user`, `project`, `bundled`) that narrow where skills are looked for. Directories are not accepted yet.
    public var sources: [String]?

    /// How many skills are listed when nothing says (the owner's choice, 2026-10-25).
    public static let defaultMaxAdvertised = 32

    public init(enabled: Bool? = nil, maxAdvertised: Int? = nil, sources: [String]? = nil) {
        self.enabled = enabled
        self.maxAdvertised = maxAdvertised
        self.sources = sources
    }

    public var isEmpty: Bool { enabled == nil && maxAdvertised == nil && sources == nil }

    /// The keys, in the order they are shown, from their declarations (``SkillsSection/settings``).
    public static let keys = settings.all.map(\.name)

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        Self.settings.named[key]?.write(self)
    }

    public var description: String {
        Self.settings.describe(self)
    }
}
