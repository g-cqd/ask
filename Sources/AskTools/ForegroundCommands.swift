internal import Synchronization

/// The commands the model is waiting on right now (roadmap 0173), so the person can send them to the background: each wait races the
/// person's request, and a request ends every wait there is, which then returns as a yield does.
final class ForegroundCommands: Sendable {
    private struct State {
        var next = 0
        var waits: [Int: CheckedContinuation<Bool, Never>] = [:]
        /// Who waits for a wait to begin (``waitUntilWaiting()``).
        var watchers: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// Runs `body`, the wait for a command, unless the person sends the command to the background first: then nil. A request that ends
    /// because the wait is cancelled is no answer, so a cancelled wait still reports itself.
    func race<Value: Sendable>(_ body: @escaping @Sendable () async throws -> Value) async throws -> Value? {
        try await withThrowingTaskGroup(of: Value??.self) { group in
            group.addTask { .some(try await body()) }
            group.addTask { await self.requested() ? .some(nil) : nil }
            while let next = try await group.next() {
                guard let answer = next else { continue }
                group.cancelAll()
                return answer
            }
            return nil
        }
    }

    /// Ends every wait; false when none was waiting.
    func sendToBackground() -> Bool {
        let resumed = state.withLock { state in
            defer { state.waits.removeAll() }
            return Array(state.waits.values)
        }
        for continuation in resumed { continuation.resume(returning: true) }
        return !resumed.isEmpty
    }

    /// Returns once a wait is there to end: what a caller that started a command waits for before sending it on.
    func waitUntilWaiting() async {
        await withCheckedContinuation { continuation in
            let now = state.withLock { state -> Bool in
                if !state.waits.isEmpty { return true }
                state.watchers.append(continuation)
                return false
            }
            if now { continuation.resume() }
        }
    }

    /// True once the person asks; false when the wait was cancelled, because the command ended first.
    private func requested() async -> Bool {
        let key = state.withLock { state -> Int in
            defer { state.next += 1 }
            return state.next
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let (cancelled, watchers) = state.withLock { state -> (Bool, [CheckedContinuation<Void, Never>]) in
                    if Task.isCancelled { return (true, []) }
                    state.waits[key] = continuation
                    defer { state.watchers.removeAll() }
                    return (false, state.watchers)
                }
                if cancelled { continuation.resume(returning: false) }
                for watcher in watchers { watcher.resume() }
            }
        } onCancel: {
            state.withLock { $0.waits.removeValue(forKey: key) }?.resume(returning: false)
        }
    }
}
