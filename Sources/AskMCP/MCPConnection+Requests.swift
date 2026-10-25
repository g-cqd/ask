internal import AemiJSON
internal import Synchronization

extension MCPConnection {
    /// Makes a request and waits for its answer: the result object's bytes, or why there is none.
    ///
    /// The wait ends on the first of: the answer, the time running out, the caller's task being cancelled, or the server going away.
    /// Time running out and being cancelled both tell the server the request is abandoned and then stop waiting, because a server
    /// that was told may carry on all the same, and its late answer is dropped.
    func request(
        _ method: String, params: [UInt8]?, timeout: Duration, beforeStart: Bool = false
    ) async throws(MCPError) -> [UInt8] {
        guard !Task.isCancelled else { throw .cancelled }
        let id = try register(method, beforeStart: beforeStart)
        enqueue(MCPWire.request(id: id, method: method, params: params))
        armTimer(id, method: method, after: timeout)
        let outcome: Result<[UInt8], MCPError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Result<[UInt8], MCPError>? in
                    guard var slot = state.slots[id] else { return .failure(.disconnected) }
                    if let result = slot.result {
                        state.slots[id] = nil
                        return result
                    }
                    slot.continuation = continuation
                    state.slots[id] = slot
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            abandon(id, .failure(.cancelled), because: "the caller no longer needs the answer")
        }
        return try outcome.get()
    }

    /// Takes the next id and makes room for its answer.
    private func register(_ method: String, beforeStart: Bool) throws(MCPError) -> Int {
        try state.withLock { state throws(MCPError) -> Int in
            guard !state.closed else { throw .disconnected }
            guard state.started || beforeStart else { throw .notStarted }
            state.nextID += 1
            state.slots[state.nextID] = Slot()
            return state.nextID
        }
    }

    /// Starts the clock on request `id`. The timer is kept with the request so that its answer, or its abandonment, stops it.
    private func armTimer(_ id: Int, method: String, after timeout: Duration) {
        let clock = clock
        let timer = Task { [weak self] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self?.abandon(id, .failure(.timedOut(method: method)), because: "timed out")
        }
        let kept = state.withLock { state -> Bool in
            guard state.slots[id] != nil else { return false }
            state.slots[id]?.timer = timer
            return true
        }
        if !kept { timer.cancel() }
    }
}
