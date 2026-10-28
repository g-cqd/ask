internal import Synchronization

/// Request timeouts with one task a connection (roadmap 0114). It sleeps until the earliest deadline, times out what has expired, and goes
/// back to sleep until the next one; a request that is answered first simply has no deadline left when it wakes.
extension MCPConnection {
    /// Starts the watchdog sleeping until `target`, unless another start for a different target won the race to be kept.
    func startWatchdog(until target: Duration) {
        let clock = clock
        let elapsed = elapsed
        let task = Task { [weak self] in
            do { try await clock.sleep(for: Swift.max(.zero, target - elapsed())) } catch { return }
            self?.watchdogWoke()
        }
        let kept = state.withLock { state -> Bool in
            guard !state.closed, state.watchdogTarget == target, state.watchdog == nil else { return false }
            state.watchdog = task
            return true
        }
        if !kept { task.cancel() }
    }

    /// Times out every request whose deadline has passed, then sleeps until the next deadline, if any.
    private func watchdogWoke() {
        let now = elapsed()
        let (expired, next) = state.withLock { state -> ([(Int, String)], Duration?) in
            state.watchdog = nil
            state.watchdogTarget = nil
            var expired: [(Int, String)] = []
            var next: Duration?
            for (id, slot) in state.slots where slot.result == nil {
                guard let deadline = slot.deadline else { continue }
                if deadline <= now {
                    expired.append((id, slot.method))
                } else {
                    next = Swift.min(next ?? deadline, deadline)
                }
            }
            if !state.closed, let next { state.watchdogTarget = next }
            return (expired, state.closed ? nil : next)
        }
        for (id, method) in expired { abandon(id, .failure(.timedOut(method: method)), because: "timed out") }
        if let next { startWatchdog(until: next) }
    }
}
