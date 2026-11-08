internal import AemiMarkdown
internal import Synchronization

/// The rows of a message's top-level blocks, kept between layouts so a streaming message lays out only the blocks that changed
/// (roadmap 0152; AemiMarkdown's "Rendering block by block"). The message is parsed whole each time, so a link definition that arrives
/// late still reaches the links above it; a block's rows are kept under what they were drawn from, not under the block's identity:
/// - the block's events, equal;
/// - every source byte they name before the first byte where the text differs from the text drawn last, so the bytes they show and
///   the lines and offsets those bytes are at are the same;
/// - its fence's fold state, and the settings the message is laid out under.
///
/// A transcript holds one, shared by its copies; it keeps the last two messages laid out, and compares equal to any other, as a cache
/// is not part of what a transcript is.
final class MarkdownRowCache: Sendable, Equatable {
    /// What a message is laid out under; another value lays every block out again.
    struct Settings: Equatable {
        var item: Int
        var columns: Int
        var inset: Int
        var firstBlockWidth: Int?
        var highlight: Bool
        var home: String?
        var paths: PathDisplay?
    }

    /// One top-level block's rows and what they were drawn from.
    struct Block: Sendable {
        var events: [MarkdownEvent]
        /// Just past the last source byte the events name.
        var reach: Int
        var fence: MarkdownMessageLayout.Fence?
        var lines: [ScreenComposer.Line]
    }

    private struct Entry {
        var settings: Settings
        var text: String
        var blocks: [Block]
    }

    private static let messages = 2
    private let entries = Mutex<[Entry]>([])
    private let laidOut = Atomic<Int>(0)

    /// How many blocks have been laid out rather than taken from the cache. For tests.
    var blocksLaidOut: Int { laidOut.load(ordering: .relaxed) }

    static func == (lhs: MarkdownRowCache, rhs: MarkdownRowCache) -> Bool { true }

    /// The blocks kept for the message laid out under `settings`, and how many leading bytes `text` shares with the text they were
    /// drawn from; none when that message was laid out under other settings or not at all.
    func kept(for settings: Settings, text: String) -> (blocks: [Block], prefix: Int) {
        entries.withLock { entries in
            guard let entry = entries.first(where: { $0.settings.item == settings.item }), entry.settings == settings
            else { return ([], 0) }
            return (entry.blocks, Self.commonPrefix(entry.text, text))
        }
    }

    /// Keeps `blocks` as the message laid out under `settings` from `text`, dropping the least recent message past the limit.
    func keep(_ blocks: [Block], for settings: Settings, text: String) {
        entries.withLock { entries in
            entries.removeAll { $0.settings.item == settings.item }
            entries.insert(Entry(settings: settings, text: text, blocks: blocks), at: 0)
            if entries.count > Self.messages { entries.removeLast(entries.count - Self.messages) }
        }
    }

    /// Counts a block laid out.
    func countLayout() { laidOut.add(1, ordering: .relaxed) }

    /// Whether `kept` may stand for a block with `events` and `fence`: the same events, naming only bytes before `prefix`.
    static func reuses(_ kept: Block, events: [MarkdownEvent], fence: MarkdownMessageLayout.Fence?, prefix: Int) -> Bool
    {
        kept.reach < prefix && kept.fence == fence && kept.events == events
    }

    /// Just past the last source byte `events` name.
    static func reach(of events: [MarkdownEvent]) -> Int {
        var reach = 0
        for event in events {
            switch event {
                case .enter(let node), .exit(let node), .leaf(let node): reach = Swift.max(reach, node.range.upperBound)
            }
        }
        return reach
    }

    /// How many leading bytes `old` and `new` share; `Int.max` when they are the same text.
    private static func commonPrefix(_ old: String, _ new: String) -> Int {
        let oldView = old.utf8
        let newView = new.utf8
        let lhs = oldView.span
        let rhs = newView.span
        let count = Swift.min(lhs.count, rhs.count)
        var index = 0
        while index < count, lhs[index] == rhs[index] { index += 1 }
        // The same text: every block it holds is as it was, the last one too.
        return index == lhs.count && index == rhs.count ? Int.max : index
    }
}
