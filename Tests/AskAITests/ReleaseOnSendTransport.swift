internal import Synchronization

@testable import AskAI

/// Wraps a ``SequencedTransport`` and lets go of a held credential lock when the request numbered `releasingAt` is sent: a lock that
/// frees up in the middle of a refresh, as another ask's does when its save finishes.
final class ReleaseOnSendTransport: HTTPTransport {
    private let inner: SequencedTransport
    private let held = Mutex<CredentialLock?>(nil)
    private let releasingAt: Int

    init(_ inner: SequencedTransport, releasing held: CredentialLock, at releasingAt: Int) {
        self.inner = inner
        self.held.withLock { $0 = held }
        self.releasingAt = releasingAt
    }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        if inner.sent.count + 1 == releasingAt {
            held.withLock {
                $0?.release()
                $0 = nil
            }
        }
        return try await inner.send(request)
    }
}
