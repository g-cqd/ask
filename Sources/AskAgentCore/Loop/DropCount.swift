internal import Synchronization

/// How many answers in a row lost their connection after some of them was shown (roadmap 0141), so a network that keeps dropping ends the
/// run after the retry policy's attempts instead of carrying on forever. A complete answer resets it.
final class DropCount: Sendable {
    private let count = Mutex(0)

    /// Counts one more drop and returns the count.
    func dropped() -> Int {
        count.withLock { value -> Int in
            value += 1
            return value
        }
    }

    /// An answer arrived whole.
    func reset() { count.withLock { $0 = 0 } }
}
