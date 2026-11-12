/// The `jobs` section of a configuration file (t232; the owner, 2026-11-06): how many finished jobs ask keeps for the job tool, with
/// their unread output. All of them by default.
public struct JobsSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `jobs.keepFinished`: the most finished jobs kept, ``noLimit`` for all of them; nil when this file does not say.
    public var keepFinished: Int?
    /// `jobs.keepFinished` `null`: every finished job.
    public static let noLimit = -1

    public init() {}

    /// The keys, in the order they are shown.
    public static let keys = ["keepFinished"]

    /// The most finished jobs kept; nil for all of them, the default.
    public var limit: Int? { keepFinished.flatMap { $0 == Self.noLimit ? nil : $0 } }

    /// `self` with every key `section` sets replaced.
    public func layered(with section: JobsSection) -> JobsSection {
        var merged = self
        merged.keepFinished = section.keepFinished ?? keepFinished
        return merged
    }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        guard key == "keepFinished" else { return nil }
        return keepFinished.map { $0 == Self.noLimit ? "null" : String($0) }
    }

    public var description: String { SectionText.describe(Self.keys, value(forKey:)) }
}
