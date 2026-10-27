public import AskAI

/// Token usage summed over a session's responses, and said briefly for a status line.
///
/// Anthropic-style accounting: `input` counts only uncached prompt tokens, so the prompt's full size is input
/// plus cache reads plus cache writes, and the cached share is reads over that total.
public struct UsageTotals: Sendable, Equatable {
    public private(set) var input = 0
    public private(set) var output = 0
    public private(set) var cacheRead = 0
    public private(set) var cacheCreation = 0
    /// Latest request's prompt plus reply, not cumulative spend. Unknown after compaction until a fresh response.
    public private(set) var contextTokens: Int?

    /// No usage yet.
    public init() {}

    /// Adds one response's usage. Counts the provider did not report add nothing.
    public mutating func add(_ usage: TokenUsage, isCompaction: Bool = false) {
        contextTokens =
            !isCompaction && usage.input != nil
            ? (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheCreation ?? 0) + (usage.output ?? 0) : nil
        input += usage.input ?? 0
        output += usage.output ?? 0
        cacheRead += usage.cacheRead ?? 0
        cacheCreation += usage.cacheCreation ?? 0
    }

    /// Every prompt token sent, cached or not.
    public var prompt: Int { input + cacheRead + cacheCreation }

    /// For example `in 13.2k (82% cached) · out 1.1k`.
    public var summary: String {
        let cached = prompt > 0 ? cacheRead * 100 / prompt : 0
        return "in \(Self.short(prompt)) (\(cached)% cached) · out \(Self.short(output))"
    }

    /// For the status line: `↑13.2k ↓1.1k`, the prompt tokens sent and the tokens received.
    public var compact: String { "↑\(Self.short(prompt)) ↓\(Self.short(output))" }

    /// 950, 1.2k, 13k, 1.4M.
    static func short(_ count: Int) -> String {
        switch count {
            case ..<1_000: return "\(count)"
            case ..<10_000: return "\(count / 1_000).\(count % 1_000 / 100)k"
            case ..<1_000_000: return "\(count / 1_000)k"
            default: return "\(count / 1_000_000).\(count % 1_000_000 / 100_000)M"
        }
    }
}
