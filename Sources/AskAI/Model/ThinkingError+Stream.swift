extension ThinkingError {
    /// Protocol clients reject an unrepresentable control without beginning a request or a task.
    var failedStream: AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: self) }
    }
}
