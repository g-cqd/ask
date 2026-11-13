internal import Synchronization

/// Work run off the screen's thread, one at a time: a request while it runs asks for one more run after it, so a burst of requests is
/// two runs, not many (the status bar's git segment, the forge's lists: roadmap 0186).
final class CoalescedRefresh: Sendable {
    private let state = Mutex((running: false, again: false))

    func request(_ work: @escaping @Sendable () async -> Void) {
        let starts = state.withLock { state in
            if state.running { state.again = true }
            defer { state.running = true }
            return !state.running
        }
        guard starts else { return }
        Task.detached(priority: .utility) {
            repeat {
                await work()
            } while self.state.withLock { state in
                defer { state.again = false }
                if !state.again { state.running = false }
                return state.again
            }
        }
    }
}
