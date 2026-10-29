internal import Synchronization

/// Connecting on first need (roadmap 0143): an interactive session starts its servers when the first message is sent, and that turn waits.
extension MCPHub {
    /// Whether a turn would wait for servers: some are not started yet, or are still connecting.
    public var isPending: Bool { !pendingServers.isEmpty }

    /// The servers not started yet or still connecting, in configuration order.
    public var pendingServers: [String] {
        status.compactMap { status in
            switch status.state {
                case .waiting, .connecting: status.name
                case .off, .ready, .searchable, .failed: nil
            }
        }
    }

    /// Starts the servers if they wait for their first need, and returns once every one has connected or failed; or after `limit`, or at
    /// once when the calling task is cancelled. A server still connecting then goes on, and its tools are offered once it is ready: one
    /// that never answers (its own timeout is a minute, for a server that is fetched first) does not hold a turn that long.
    /// - Returns: whether every server has settled.
    @discardableResult
    public func connect(waitingAtMost limit: Duration? = nil) async -> Bool {
        state.withLock { state in
            guard !state.started else { return }
            state.started = true
            launch(&state)
        }
        let waiter = MCPConnectWaiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.hold(continuation)
                if Task.isCancelled { waiter.release() }
                Task {
                    await self.waitUntilSettled()
                    waiter.release()
                }
                if let limit {
                    Task {
                        try? await Task.sleep(for: limit)
                        waiter.release()
                    }
                }
            }
        } onCancel: {
            waiter.release()
        }
        return !isPending
    }
}
