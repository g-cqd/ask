/// The `hooks` section of a configuration file (roadmap 0192, ADR-0143). Only the person's own file may set it.
public struct HooksSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `hooks.maxContinues`: how many times hooks may continue one run that would have ended; each also counts against the turn limit.
    public var maxContinues: Int?

    /// How many times when nothing says (the owner's choice, 2026-11-02).
    public static let defaultMaxContinues = 3
    /// The most a file may ask for.
    static let mostContinues = 100

    public init(maxContinues: Int? = nil) { self.maxContinues = maxContinues }

    /// The keys, in the order they are shown.
    public static let keys = ["maxContinues"]

    /// How many continues a run is allowed.
    public var continues: Int { maxContinues ?? Self.defaultMaxContinues }

    /// `self` with every key `section` sets replaced.
    public func layered(with section: HooksSection) -> HooksSection {
        HooksSection(maxContinues: section.maxContinues ?? maxContinues)
    }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        key == "maxContinues" ? maxContinues.map(String.init) : nil
    }

    public var description: String { SectionText.describe(Self.keys, value(forKey:)) }
}
