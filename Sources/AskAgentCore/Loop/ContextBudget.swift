/// How much a model may write, when its conversation is compacted, and how much a compaction keeps, derived from its
/// context window so a small local model compacts before the server refuses it.
///
/// With no window known the long-standing defaults hold. With one, the reply is capped at a quarter of the window,
/// compaction starts once the context would leave less than a reply and a margin (a tenth of the window, at least
/// 4,096 tokens), and the tail a compaction keeps word for word is at most a quarter of the window (about four bytes
/// a token). A threshold the user asked for is never raised, and compaction turned off stays off: a request refused
/// for its length is compacted and sent again by the loop either way.
public struct ContextBudget: Sendable, Equatable {
    /// The longest reply one request may ask for.
    public let maximumTokens: Int
    /// The context size that triggers compaction, or nil for only when a request is refused for its length.
    public let compactAtTokens: Int?
    /// How much recent text a compaction keeps word for word, in bytes.
    public let keepRecentBytes: Int
    /// How much tool output one turn may add, in bytes, shared by that turn's calls; nil when no window is known.
    /// A turn's results cannot be split by compaction, so they must fit the window together (diary 14: four files
    /// read in one turn came to 13,451 tokens on an 8,192-token server).
    public let toolOutputBytes: Int?

    /// The reply limit when nothing narrower is known.
    public static let defaultMaximumTokens = 16_384
    /// The kept tail when the window is large enough: about 20,000 tokens.
    public static let defaultKeepRecentBytes = 80_000

    /// A budget with these values exactly.
    init(maximumTokens: Int, compactAtTokens: Int?, keepRecentBytes: Int, toolOutputBytes: Int?) {
        self.maximumTokens = maximumTokens
        self.compactAtTokens = compactAtTokens
        self.keepRecentBytes = keepRecentBytes
        self.toolOutputBytes = toolOutputBytes
    }

    /// The budget for a model with `contextWindow` tokens and its own output limit, given the threshold the user chose.
    public init(contextWindow: Int?, maxOutputTokens: Int?, requestedCompactAt: Int?) {
        guard let window = contextWindow, window > 0 else {
            maximumTokens = maxOutputTokens ?? Self.defaultMaximumTokens
            compactAtTokens = requestedCompactAt
            keepRecentBytes = Self.defaultKeepRecentBytes
            toolOutputBytes = nil
            return
        }
        let reply = Swift.max(1, Swift.min(maxOutputTokens ?? Self.defaultMaximumTokens, window / 4))
        let margin = Swift.max(window / 10, 4_096)
        let fits = Swift.max(1, window - reply - margin)
        maximumTokens = reply
        compactAtTokens = requestedCompactAt.map { Swift.min($0, fits) }
        keepRecentBytes = Swift.max(1, Swift.min(Self.defaultKeepRecentBytes, window))
        // About a quarter of the window in tokens, at four bytes a token.
        toolOutputBytes = Swift.max(512, window)
    }
}
