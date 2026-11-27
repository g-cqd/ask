internal import Synchronization

/// Telling the model when a job it left running ends (owner, 2026-11-27): it may go on with something else instead of waiting, and
/// an end that comes while it is idle starts its next turn.
extension Job {
    /// The model is told when the job ends (`true`), or not.
    func notifyOnEnd(_ notifies: Bool) { state.withLock { $0.notifies = notifies } }

    /// The model has seen the job's end: a tool returned it.
    func markEndReported() { state.withLock { $0.endReported = true } }

    /// Whether the model is to be told of the job's end now: it notifies, it has ended, and its end was not reported. True once:
    /// telling counts as reporting.
    func claimEndNotice() -> Bool {
        state.withLock { state in
            guard state.notifies, state.status != .running, !state.endReported else { return false }
            state.endReported = true
            return true
        }
    }
}
