internal import Synchronization

/// A number of places that may be held at once (ADR-0156): a script's calls in flight, the scripts running in a process. One
/// that asks when all are held waits its turn, in the order asked; a wait that is cancelled takes no place.
final class CodemodeLimiter: Sendable {
    private struct State {
        var free: Int
        var waiting: [(id: Int, resume: CheckedContinuation<Bool, Never>)] = []
        var asked = 0
        var watchers: [(id: Int, count: Int, resume: CheckedContinuation<Void, Never>)] = []
    }

    private let state: Mutex<State>

    init(_ places: Int) { state = Mutex(State(free: max(1, places))) }

    /// The places nobody holds.
    var free: Int { state.withLock { $0.free } }

    /// Takes a place, waiting for one when all are held: true once it has one, false when the task was cancelled first.
    func acquire() async -> Bool {
        let id = state.withLock { state -> Int in
            state.asked += 1
            return state.asked
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { resume in
                let (taken, watching) = state.withLock { state -> (Bool?, [CheckedContinuation<Void, Never>]) in
                    if Task.isCancelled { return (false, []) }
                    if state.free > 0 {
                        state.free -= 1
                        return (true, [])
                    }
                    state.waiting.append((id, resume))
                    let reached = state.watchers.filter { $0.count <= state.waiting.count }.map(\.resume)
                    state.watchers.removeAll { $0.count <= state.waiting.count }
                    return (nil, reached)
                }
                if let taken { resume.resume(returning: taken) }
                // @dl:accept -- two waits that a cancellation ends, built the same way; what each waits for is its own
                for watcher in watching { watcher.resume() }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                state.waiting.firstIndex { $0.id == id }.map { state.waiting.remove(at: $0).resume }
            }
            waiter?.resume(returning: false)
        }
    }

    /// Gives a place back: to the one that has waited longest, or to nobody.
    func release() {
        let next = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard state.waiting.isEmpty else { return state.waiting.removeFirst().resume }
            state.free += 1
            return nil
        }
        next?.resume(returning: true)
    }

    /// Returns once `count` are waiting for a place, or the task is cancelled: for a test to wait on without a clock, and
    /// without being held past its time limit when nothing ever waits.
    func waiting(_ count: Int) async {
        let id = state.withLock { state -> Int in
            state.asked += 1
            return state.asked
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { resume in
                let already = state.withLock { state -> Bool in
                    guard state.waiting.count < count, !Task.isCancelled else { return true }
                    state.watchers.append((id, count, resume))
                    return false
                }
                if already { resume.resume() }
            }
        } onCancel: {
            let watcher = state.withLock { state in
                state.watchers.firstIndex { $0.id == id }.map { state.watchers.remove(at: $0).resume }
            }
            watcher?.resume()
        }
    }
}
