internal import Synchronization

/// A continuation resumed once, by whichever comes first: the servers settling, the wait's limit, or the turn being cancelled
/// (``MCPHub/connect(waitingAtMost:)``).
final class MCPConnectWaiter: Sendable {
    private let continuation = Mutex<CheckedContinuation<Void, Never>?>(nil)

    func hold(_ held: CheckedContinuation<Void, Never>) { continuation.withLock { $0 = held } }

    func release() { continuation.withLock { $0.take() }?.resume() }
}
