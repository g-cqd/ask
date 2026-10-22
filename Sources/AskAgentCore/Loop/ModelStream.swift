public import AskAI

/// Streams for providers that must do asynchronous work before the request can be sent: a credential refresh, or a
/// lookup the first frame must not wait for.
public enum ModelStream {
    /// Runs `prepare`, then forwards every event of the stream it returns. A failure in either ends the stream with
    /// that failure, and cancelling the consumer cancels the work, including a stream already being forwarded.
    /// - Parameter prepare: does the work and returns the stream to forward; nothing is sent before it returns.
    /// - Returns: the forwarded stream.
    public static func after(
        _ prepare: @escaping @Sendable () async throws -> AsyncThrowingStream<ModelEvent, any Error>
    ) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await prepare()
                    try Task.checkCancellation()
                    for try await event in stream { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
