import Foundation
import Synchronization

@testable import AskAI

/// Answers requests with scripted responses in order, and remembers every request.
///
/// A sign-in is a conversation: a start, some polls, an exchange. The last response repeats once the script runs out,
/// so a flow that polls forever against "pending" is seen polling forever rather than crashing the test.
final class SequencedTransport: HTTPTransport {
    enum Reply {
        case json(Int, String)
        case failure(any Error)
    }

    private let replies: [Reply]
    private let state = Mutex<(next: Int, sent: [HTTPRequest])>((0, []))

    init(_ replies: [Reply]) { self.replies = replies }

    /// Every request sent, in order.
    var sent: [HTTPRequest] { state.withLock { $0.sent } }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        let reply = state.withLock { state in
            state.sent.append(request)
            defer { state.next += 1 }
            return replies[Swift.min(state.next, replies.count - 1)]
        }
        switch reply {
            case .failure(let error): throw error
            case .json(let status, let text):
                let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
                continuation.yield(Array(text.utf8))
                continuation.finish()
                return HTTPStreamingResponse(status: status, headers: [:], body: body)
        }
    }
}
