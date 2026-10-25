internal import Synchronization

/// Counts calls made from a `@Sendable` closure.
final class CallCounter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func bump() { value.withLock { $0 += 1 } }
}
