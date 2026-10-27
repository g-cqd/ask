internal import Synchronization

/// Non-consuming output notifications for a focused job lane, independent of the model's unread output cursor.
extension Job {
    /// An initial notification, then one whenever output arrives; ends with the job. Slow readers see only the newest
    /// notification and read the current bounded tail. Cancellation unregisters the reader without stopping the job.
    public func outputChanges() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let key = state.withLock { state in
                state.nextOutputObserver += 1
                let key = state.nextOutputObserver
                continuation.yield(())
                if state.status == .running {
                    state.outputObservers[key] = continuation
                } else {
                    continuation.finish()
                }
                return key
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.outputObservers[key] = nil }
            }
        }
    }
}
