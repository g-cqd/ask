/// How the loop retries a request that failed transiently.
///
/// Exponential backoff from `baseDelay`, doubling per attempt, capped at `maximumDelay`. A provider's own
/// `retry-after` wins when it gave one, capped at `maximumRequestedDelay` so a hostile or broken value cannot
/// stall a run indefinitely.
public struct RetryPolicy: Sendable, Equatable {
    /// Total attempts, the first included.
    public var maximumAttempts: Int
    public var baseDelay: Duration
    public var maximumDelay: Duration
    public var maximumRequestedDelay: Duration

    /// A policy with these bounds.
    public init(maximumAttempts: Int, baseDelay: Duration, maximumDelay: Duration, maximumRequestedDelay: Duration) {
        self.maximumAttempts = Swift.max(1, maximumAttempts)
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.maximumRequestedDelay = maximumRequestedDelay
    }

    /// Five attempts: waits of 1, 2, 4 and 8 seconds, or what the provider asked for, up to two minutes.
    public static let standard = RetryPolicy(
        maximumAttempts: 5, baseDelay: .seconds(1), maximumDelay: .seconds(30), maximumRequestedDelay: .seconds(120))

    /// The wait before attempt `attempt + 1`, after `attempt` failed (attempts count from 1).
    public func delay(after attempt: Int, requested: Duration?) -> Duration {
        if let requested { return Swift.min(Swift.max(.zero, requested), maximumRequestedDelay) }
        var delay = baseDelay
        for _ in 1 ..< Swift.max(1, attempt) where delay < maximumDelay { delay *= 2 }
        return Swift.min(delay, maximumDelay)
    }
}
