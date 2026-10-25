internal import Foundation

@testable import AskAI

/// Runs `before` just ahead of each request, then answers from `inner`: a change another process makes while a request is in flight.
final class HookedTransport: HTTPTransport {
    private let inner: SequencedTransport
    private let before: @Sendable () -> Void

    init(_ inner: SequencedTransport, before: @escaping @Sendable () -> Void) {
        self.inner = inner
        self.before = before
    }

    var sent: [HTTPRequest] { inner.sent }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        before()
        return try await inner.send(request)
    }
}
