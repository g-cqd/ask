import Foundation
import Synchronization

@testable import AskAI

/// Synthetic requests only: never reads an account or sends a network request.
final class CopilotTestTransport: HTTPTransport {
    private let seen = Mutex<[HTTPRequest]>([])
    private let handler: @Sendable (HTTPRequest) throws -> HTTPStreamingResponse
    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPStreamingResponse) { self.handler = handler }
    var requests: [HTTPRequest] { seen.withLock { $0 } }
    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        seen.withLock { $0.append(request) }
        return try handler(request)
    }
    static func reply(_ text: String, status: Int = 200) -> HTTPStreamingResponse {
        HTTPStreamingResponse(
            status: status, headers: [:],
            body: AsyncThrowingStream { stream in
                stream.yield(Array(text.utf8))
                stream.finish()
            })
    }
}
