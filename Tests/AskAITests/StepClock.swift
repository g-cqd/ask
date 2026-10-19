import Synchronization

/// A clock whose sleeps return at once, are recorded, and move its time forward, so a deadline passes in no time and
/// a test sees every wait the code asked for.
final class StepClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let state = Mutex<(now: Duration, sleeps: [Duration])>((.zero, []))

    var now: Instant { Instant(offset: state.withLock { $0.now }) }
    var minimumResolution: Duration { .zero }
    /// Every wait requested, in order.
    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(deadline.offset - state.now)
            state.now = Swift.max(state.now, deadline.offset)
        }
    }
}
