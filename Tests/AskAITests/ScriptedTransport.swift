import Foundation
import Synchronization
import Testing

@testable import AskAI

/// Answers every request with one scripted response, and remembers the request.
final class ScriptedTransport: HTTPTransport {
    private let status: Int
    private let chunks: [String]
    private let lastRequest = Mutex<HTTPRequest?>(nil)

    private let headers: [String: String]
    /// Thrown by the body after the chunks, as a connection that breaks part way.
    private let failure: (any Error & Sendable)?

    init(status: Int, chunks: [String], headers: [String: String] = [:], failure: (any Error & Sendable)? = nil) {
        self.headers = headers
        self.failure = failure
        self.status = status
        self.chunks = chunks
    }

    var sent: HTTPRequest? { lastRequest.withLock { $0 } }

    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        lastRequest.withLock { $0 = request }
        let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        for chunk in chunks { continuation.yield(Array(chunk.utf8)) }
        continuation.finish(throwing: failure)
        return HTTPStreamingResponse(status: status, headers: headers, body: body)
    }
}
