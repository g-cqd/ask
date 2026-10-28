internal import AemiJSON
internal import Synchronization

extension MCPConnection {
    /// Makes a request and waits for its answer: the result object, parsed once with the message it came in, or why there is none.
    ///
    /// The wait ends on the first of: the answer, the time running out, the caller's task being cancelled, or the server going away.
    /// Time running out and being cancelled both tell the server the request is abandoned and then stop waiting, because a server
    /// that was told may carry on all the same, and its late answer is dropped.
    func request(
        _ method: String, params: [UInt8]?, timeout: Duration, beforeStart: Bool = false
    ) async throws(MCPError) -> JSON {
        guard !Task.isCancelled else { throw .cancelled }
        let id = try register(method, beforeStart: beforeStart, timeout: timeout)
        await send(MCPWire.request(id: id, method: method, params: params))
        let outcome: Result<JSON, MCPError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Result<JSON, MCPError>? in
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

    /// Takes the next id, makes room for its answer, and starts its clock: the watchdog is moved earlier only when this deadline comes
    /// before the one it sleeps until, which with one timeout for every request is never once it runs.
    private func register(_ method: String, beforeStart: Bool, timeout: Duration) throws(MCPError) -> Int {
        let deadline = elapsed() + timeout
        let (id, rearm) = try state.withLock { state throws(MCPError) -> (Int, Bool) in
            guard !state.closed else { throw .disconnected }
            guard state.started || beforeStart else { throw .notStarted }
            state.nextID += 1
            state.slots[state.nextID] = Slot(deadline: deadline, method: method)
            guard state.watchdogTarget.map({ deadline < $0 }) ?? true else { return (state.nextID, false) }
            state.watchdog?.cancel()
            state.watchdog = nil
            state.watchdogTarget = deadline
            return (state.nextID, true)
        }
        if rearm { startWatchdog(until: deadline) }
        return id
    }
}
