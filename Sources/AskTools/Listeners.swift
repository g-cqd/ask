internal import Synchronization

/// Streams handed to whoever listens, each sent every value from then on, and forgotten once its listener stops.
final class Listeners<Element: Sendable>: Sendable {
    private let streams = Mutex<[Int: AsyncStream<Element>.Continuation]>([:])
    private let next = Atomic<Int>(0)

    /// A new listener's stream; `first`, when given, is sent to it at once.
    func stream(
        buffering policy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
        first: Element? = nil
    ) -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: policy) { continuation in
            let key = next.wrappingAdd(1, ordering: .relaxed).newValue
            streams.withLock { $0[key] = continuation }
            continuation.onTermination = { [weak self] _ in self?.streams.withLock { $0[key] = nil } }
            if let first { continuation.yield(first) }
        }
    }

    /// Sends `value` to every listener.
    func send(_ value: Element) { streams.withLock { for continuation in $0.values { continuation.yield(value) } } }
}
