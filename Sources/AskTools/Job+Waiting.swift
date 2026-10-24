internal import Synchronization

/// Waiting on a job: for a text in its output, or for its end. The job resumes waiters itself, as output
/// arrives and when it ends.
extension Job {
    /// Waits until the output not yet seen, or output still to come, contains `needle`; or, with no needle,
    /// until the job ends. A job that ends first ends the wait.
    /// - Parameter needle: the bytes to find, or nil to wait for the end.
    /// - Returns: what the wait ended on. Cancelling the task ends it as `.cancelled`.
    func wait(for needle: [UInt8]?) async -> WaitResult {
        let key = state.withLock { state -> Int in
            defer { state.nextWaiter += 1 }
            return state.nextWaiter
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate: WaitResult? = state.withLock { state in
                    if let needle, state.unread.contains(needle) { return .found }
                    if state.status != .running { return .ended }
                    if Task.isCancelled { return .cancelled }
                    // Seeded with the end of all recent output, shown or not, so a text that began before the wait
                    // and ends in the next chunk is still found.
                    let carry = needle.map { Array(state.recent.suffix(Swift.max(0, $0.count - 1))) } ?? []
                    state.waiters[key] = Waiter(needle: needle, carry: carry, continuation: continuation)
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: key) }
            waiter?.continuation.resume(returning: .cancelled)
        }
    }

    /// Waits for the job to end, whatever happens to the calling task: for cleanup after a stop.
    func ended() async {
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<WaitResult, Never>) in
            let key: Int? = state.withLock { state in
                guard state.status == .running else { return nil }
                defer { state.nextWaiter += 1 }
                state.waiters[state.nextWaiter] = Waiter(needle: nil, continuation: continuation)
                return state.nextWaiter
            }
            if key == nil { continuation.resume(returning: .ended) }
        }
    }
}
