/// How long the screen's work has gone on without a pause (notes n59 and n61).
struct LongAction {
    /// When work counts as long (the owner, 2026-11-11): what a `!` command waits before it is a job, too.
    static let after = Duration.seconds(5)

    private var since: ContinuousClock.Instant?

    /// Whether work that has gone on `elapsed` is long.
    static func isLong(_ elapsed: Duration) -> Bool { elapsed >= after }

    /// How long the work has gone on at `now`, `working` or not; nil when it is not. Work that stops and starts again counts anew.
    mutating func update(working: Bool, at now: ContinuousClock.Instant) -> Duration? {
        guard working else {
            since = nil
            return nil
        }
        let start = since ?? now
        since = start
        return now - start
    }
}
