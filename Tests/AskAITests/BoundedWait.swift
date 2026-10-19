internal import Synchronization

/// Waits for a task for a limited time, so a path that should end but does not fails the test in seconds instead of
/// hanging the suite.
enum BoundedWait {
    /// How `task` ended, or nil if it had not within `limit`. On a timeout `release` is called to unblock it, and the
    /// wait does not then wait for the task: one that never started would never end.
    static func result<Success: Sendable>(
        of task: Task<Success, any Error>, within limit: Duration = .seconds(5), release: @escaping @Sendable () -> Void
    ) async -> Result<Success, any Error>? {
        let decided = Mutex(false)
        func first() -> Bool {
            decided.withLock { already in
                defer { already = true }
                return !already
            }
        }
        return await withCheckedContinuation { continuation in
            Task {
                let outcome = await task.result
                if first() { continuation.resume(returning: outcome) }
            }
            Task {
                try? await Task.sleep(for: limit)
                if first() {
                    release()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
