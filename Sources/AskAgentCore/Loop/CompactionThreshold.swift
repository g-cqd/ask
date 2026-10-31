/// When a conversation is compacted (roadmap 0104): once its context reaches a share of the model's window (`0.75`), or a number of
/// tokens (`150000`). A number up to 1 is a share, in whole percents; above it, tokens (roadmap 0118). `"75%"` is still read. `0` tokens means only when the window is full and a request is refused for its length. Whatever is asked,
/// ``ContextBudget`` still compacts before the next request would not fit.
public enum CompactionThreshold: Sendable, Equatable, CustomStringConvertible {
    /// A context size in tokens; 0 is "only when the window is full".
    case tokens(Int)
    /// A percentage of the model's context window, 1 to 100.
    case share(Int)

    /// Three quarters of the window: on a 200,000-token window this is the 150,000 tokens ask used before it took a share.
    public static let standard = Self.share(75)

    /// A number as written for `--compact-at` or `ASK_COMPACT_AT` (`0.75`, `150000`, `0`), or a share as before (`"75%"`, 1 to 100);
    /// nil for anything else.
    public init?(parsing text: String) {
        let trimmed = text.trimmingWhitespace()
        if trimmed.hasSuffix("%") {
            guard let percent = Int(String(trimmed.dropLast()).trimmingWhitespace()), (1 ... 100).contains(percent)
            else { return nil }
            self = .share(percent)
        } else {
            guard let number = Double(trimmed) else { return nil }
            self.init(number: number)
        }
    }

    /// `0`: only when the window is full; above 0 and up to 1: that share of the window, in whole percents (`0.95`); above 1: that many
    /// tokens, a whole number. Nil for anything else.
    public init?(number: Double) {
        guard number.isFinite, number >= 0 else { return nil }
        if number == 0 {
            self = .tokens(0)
        } else if number <= 1 {
            let percent = (number * 100).rounded()
            guard abs(percent - number * 100) < 1e-9 else { return nil }
            self = .share(Int(percent))
        } else {
            guard number == number.rounded(), number <= Double(Int.max / 2) else { return nil }
            self = .tokens(Int(number))
        }
    }

    /// What `--compact-at`, `ASK_COMPACT_AT` and a file accept, for an error message.
    public static let expected =
        "a share of the window from 0.01 to 1 (0.75), a number of tokens above 1 (150000), or 0 for only when the window is full"

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
            case .share(let percent): percent == 100 ? "1" : "0." + (percent < 10 ? "0" : "") + Self.trimmed(percent)
        }
    }

    /// A percent's digits after "0.", without a trailing zero: 50 is "5", 75 is "75", 5 is "5" (after the "0" for tenths).
    private static func trimmed(_ percent: Int) -> String {
        percent % 10 == 0 ? String(percent / 10) : String(percent)
    }
}
