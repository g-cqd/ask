internal import Foundation
internal import Synchronization

@testable import AskAI

/// Answers one request after the test says so, and tells the test when the request has arrived.
///
/// A refresh is a read, a network call and a save. To test what happens to the save when the world changes during the
/// call, the call must be held open at a known point: this holds it, with no sleeping and no guess about timing.
final class GatedTransport: HTTPTransport {
    private let status: Int
    private let text: String
    private let arrived: AsyncStream<Void>
    private let arrivedContinuation: AsyncStream<Void>.Continuation
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation
    private let requests = Mutex<[HTTPRequest]>([])

    init(status: Int, text: String) {
        self.status = status
        self.text = text
        (arrived, arrivedContinuation) = AsyncStream<Void>.makeStream()
        (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    }

    /// Every request received.
    var sent: [HTTPRequest] { requests.withLock { $0 } }

    /// Returns once a request is being held.
    func waitUntilRequested() async {
        for await _ in arrived { return }
    }

    /// Lets the held request be answered.
    func release() { gateContinuation.yield() }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        requests.withLock { $0.append(request) }
        arrivedContinuation.yield()
        for await _ in gate { break }
        let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        continuation.yield(Array(text.utf8))
        continuation.finish()
        return HTTPStreamingResponse(status: status, headers: [:], body: body)
    }
}
