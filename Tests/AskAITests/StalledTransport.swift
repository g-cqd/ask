import Testing

@testable import AskAI

/// A transport that never answers, until the task waiting on it is cancelled.
struct StalledTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        let (silence, source) = AsyncStream<Void>.makeStream()
        defer { source.finish() }
        for await _ in silence {}  // a stream nothing yields to ends only when the task is cancelled
        throw CancellationError()
    }
}
