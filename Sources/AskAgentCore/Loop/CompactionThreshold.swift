/// When a conversation is compacted (roadmap 0104): once its context reaches a share of the model's window (`"75%"`), or a number of
/// tokens (`150000`). `0` tokens means only when the window is full and a request is refused for its length. Whatever is asked,
/// ``ContextBudget`` still compacts before the next request would not fit.
public enum CompactionThreshold: Sendable, Equatable, CustomStringConvertible {
    /// A context size in tokens; 0 is "only when the window is full".
    case tokens(Int)
    /// A percentage of the model's context window, 1 to 100.
    case share(Int)

    /// Three quarters of the window: on a 200,000-token window this is the 150,000 tokens ask used before it took a share.
    public static let standard = Self.share(75)

    /// `"75%"` (1 to 100) or a whole number of tokens of at least 0; nil for anything else.
    public init?(parsing text: String) {
        let trimmed = text.trimmingWhitespace()
        if trimmed.hasSuffix("%") {
            guard let percent = Int(String(trimmed.dropLast()).trimmingWhitespace()), (1 ... 100).contains(percent)
            else { return nil }
            self = .share(percent)
        } else {
            guard let tokens = Int(trimmed), tokens >= 0 else { return nil }
            self = .tokens(tokens)
        }
    }

    /// What `--compact-at`, `ASK_COMPACT_AT` and a file accept, for an error message.
    public static let expected =
        "a share of the window from 1% to 100% (\"75%\"), or a number of tokens (0: only when the window is full)"

    /// The threshold in tokens for a window of `window` tokens, or nil for "only when full". A share with no window known falls back to
    /// ``AgentSettings/defaultCompactAtTokens``.
    public func tokens(window: Int?) -> Int? {
        switch self {
            case .tokens(let count): count > 0 ? count : nil
            case .share(let percent):
                window.flatMap { $0 > 0 ? $0 * percent / 100 : nil } ?? AgentSettings.defaultCompactAtTokens
        }
    }

    /// The share, when this is one.
    public var percent: Int? {
        if case .share(let percent) = self { return percent }
        return nil
    }

    public var description: String {
        switch self {
            case .tokens(let count): String(count)
            case .share(let percent): "\(percent)%"
        }
    }
}
