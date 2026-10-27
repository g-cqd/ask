internal import Foundation

/// Monotonic elapsed time and a single-cell animation frame for one live block.
struct BlockProgress: Sendable, Equatable {
    let started: ContinuousClock.Instant
    var sampled: ContinuousClock.Instant
    var ended: ContinuousClock.Instant?
    var frame = 0
    var spinner: SpinnerStyle = .line

    init(at instant: ContinuousClock.Instant, spinner: SpinnerStyle = .line) {
        started = instant
        sampled = instant
        self.spinner = spinner.resolved()
    }

    /// No time for fast operations; completed operations use their frozen duration.
    var duration: String? { duration(localized: true) }

    func duration(localized: Bool, locale: Locale = .current) -> String? {
        let elapsed = started.duration(to: ended ?? sampled)
        guard elapsed > .seconds(1) else { return nil }
        let seconds = elapsed.components.seconds
        if localized {
            return Duration.seconds(seconds)
                .formatted(
                    Duration.UnitsFormatStyle(
                        allowedUnits: [.hours, .minutes, .seconds], width: .abbreviated,
                        zeroValueUnits: .hide
                    )
                    .locale(locale))
        }
        func padded(_ value: Int64) -> String { value < 10 ? "0\(value)" : String(value) }
        if seconds >= 3600 { return "\(seconds / 3600):\(padded(seconds / 60 % 60)):\(padded(seconds % 60))" }
        if seconds >= 60 { return "\(seconds / 60):\(padded(seconds % 60))" }
        return String(seconds)
    }

    /// The current animation frame, strictly width 1.
    var indicator: String {
        let frames = spinner.frames
        guard !frames.isEmpty else { return "|" }
        return frames[frame % frames.count]
    }
}
