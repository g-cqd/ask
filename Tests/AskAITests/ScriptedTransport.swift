import Foundation
import Synchronization
import Testing

@testable import AskAI

/// Answers every request with one scripted response, and remembers the request.
final class ScriptedTransport: HTTPTransport {
    private let status: Int
    private let chunks: [String]
    private let lastRequest = Mutex<HTTPRequest?>(nil)

    init(status: Int, chunks: [String]) {
        self.status = status
        self.chunks = chunks
    }

    var sent: HTTPRequest? { lastRequest.withLock { $0 } }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        lastRequest.withLock { $0 = request }
        let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        for chunk in chunks { continuation.yield(Array(chunk.utf8)) }
        continuation.finish()
        return HTTPStreamingResponse(status: status, body: body)
    }
}
