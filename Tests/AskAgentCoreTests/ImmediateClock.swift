import Synchronization

/// A clock whose sleeps return at once and are recorded, so a test sees every wait the code asked for and can
/// never hang on a wait it did not expect.
final class ImmediateClock: Clock {
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
