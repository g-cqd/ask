/// The `threads` section of a configuration file (roadmap 0195): how many threads may work at once, how deep they nest, and how they
/// are named.
public struct ThreadsSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// How a thread is named.
    public enum Names: String, Sendable, Equatable, CaseIterable {
        /// By Apple's on-device model, from its task, where it is available; `thread-N` elsewhere.
        case onDevice
        /// `thread-N`.
        case numbered
    }

    /// `threads.max`: how many threads may work at once; `/thread` past it is refused.
    public var max: Int?
    /// `threads.depth`: how deep threads may nest; `/thread` in a thread that deep is refused.
    public var depth: Int?
    /// `threads.names`: how a thread is named.
    public var names: Names?
    /// `threads.mergedShownFor`: how long a merged thread stays in the sidebar, as written (`"30m"`, `"2h"`, `"1d"`, `"always"`).
    public var mergedShownFor: String?

    public static let defaultMax = 4
    public static let defaultDepth = 3
    static let mostAtOnce = 16
    static let deepest = 8

    public init(max: Int? = nil, depth: Int? = nil, names: Names? = nil, mergedShownFor: String? = nil) {
        self.max = max
        self.depth = depth
        self.names = names
        self.mergedShownFor = mergedShownFor
    }

    /// The keys, in the order they are shown.
    public static let keys = ["max", "depth", "names", "mergedShownFor"]

    public var atOnce: Int { max ?? Self.defaultMax }
    public var nesting: Int { depth ?? Self.defaultDepth }
    public var naming: Names { names ?? .onDevice }
    /// How long a merged thread stays listed; nil for always.
    public var mergedListing: Duration? {
        guard let written = mergedShownFor else { return .seconds(86_400) }
        return Self.duration(written) ?? .seconds(86_400)
    }

    /// `"30m"`, `"2h"` or `"1d"` as a duration, `"always"` as nil (`.some(nil)`); nil when it is neither.
    static func duration(_ written: String) -> Duration?? {
        if written == "always" { return .some(nil) }
        let units: [Character: Int64] = ["m": 60, "h": 3_600, "d": 86_400]
        guard let unit = written.last.flatMap({ units[$0] }), let count = Int64(written.dropLast()), count > 0 else {
            return nil
        }
        // @dl:accept -- every section layers its keys this way; the key lists are the data
        return .some(.seconds(count * unit))
    }

    /// `self` with every key `section` sets replaced.
    // @dl:accept -- each section layers its keys the same way; the key lists are the data
    public func layered(with section: ThreadsSection) -> ThreadsSection {
        ThreadsSection(
            max: section.max ?? max,
            depth: section.depth ?? depth,
            names: section.names ?? names,
            mergedShownFor: section.mergedShownFor ?? mergedShownFor
        )
    }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        switch key {
            case "max": max.map(String.init)
            case "depth": depth.map(String.init)
            case "names": names?.rawValue
            case "mergedShownFor": mergedShownFor
            default: nil
        }
    }

    public var description: String { SectionText.describe(Self.keys, value(forKey:)) }
}
