/// Monotonic elapsed time and a single-cell animation frame for one live block.
struct BlockProgress: Sendable, Equatable {
    let started: ContinuousClock.Instant
    var sampled: ContinuousClock.Instant
    var ended: ContinuousClock.Instant?
    var frame = 0

    init(at instant: ContinuousClock.Instant) {
        started = instant
        sampled = instant
    }

    var duration: String {
        let seconds = Swift.max(0, started.duration(to: ended ?? sampled).components.seconds)
        func padded(_ value: Int64) -> String { value < 10 ? "0\(value)" : String(value) }
        return "\(padded(seconds / 3600)):\(padded(seconds / 60 % 60)):\(padded(seconds % 60))"
    }

    /// ASCII frames have one cell even in terminals with ambiguous-width Unicode configured wide.
    var indicator: String { ["|", "/", "-", "\\"][frame % 4] }
}
