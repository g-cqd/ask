/// The `skills` section of a configuration file (roadmap 0061). Every key is optional, and a layer that sets one replaces it.
public struct SkillsSection: Sendable, Equatable, CustomStringConvertible {
    /// `skills.enabled`: whether skills are advertised and the `skill` tool offered at all. Off costs the model nothing: no block, no tool.
    public var enabled: Bool?
    /// `skills.maxAdvertised`: how many skills the system prompt lists. The rest can still be loaded by name; the prompt says how many are not listed.
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

    /// The keys, in the order they are shown.
    public static let keys = ["enabled", "maxAdvertised", "sources"]

    /// `self` with every key `section` sets replaced.
    public func layered(with section: SkillsSection) -> SkillsSection {
        SkillsSection(
            // @dl:accept -- each section layers its keys the same way; the key lists are the data
            enabled: section.enabled ?? enabled, maxAdvertised: section.maxAdvertised ?? maxAdvertised,
            sources: section.sources ?? sources)
    }

    public var description: String {
        var parts: [String] = []
        // @dl:accept -- one line per key, as data
        if let enabled { parts.append("enabled \(enabled ? "on" : "off")") }
        if let maxAdvertised { parts.append("maxAdvertised \(maxAdvertised)") }
        if let sources { parts.append("sources \(sources.joined(separator: ", "))") }
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
