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
        return localized ? DurationText.localized(seconds, locale: locale) : DurationText.clock(seconds)
    }

    /// The current animation frame, strictly width 1.
    var indicator: String {
        let frames = spinner.frames
        guard !frames.isEmpty else { return "|" }
        return frames[frame % frames.count]
    }
}
