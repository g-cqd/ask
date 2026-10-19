extension AsyncThrowingStream where Failure == any Error, Element: Sendable {
    /// A stream that `produce` feeds from its own task.
    ///
    /// The stream finishes when `produce` returns and fails with what it throws, and the task is cancelled when the
    /// consumer stops listening, so an abandoned request does not keep running.
    static func producing(_ produce: @escaping @Sendable (_ yield: (Element) -> Void) async throws -> Void) -> Self {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await produce { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
