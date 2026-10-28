internal import Synchronization

/// Sending, in order, without a task in between (roadmap 0114). Whoever has a message to send and finds nobody sending sends it at once,
/// then whatever was queued meanwhile; anyone who finds a send under way queues behind it. Order is the order messages were claimed in, as it
/// was with the queue this replaced, and a transport's `send` returns as soon as the message is handed over, so nobody waits long.
extension MCPConnection {
    /// Sends `message` now if nothing else is being sent, after which this caller sends what was queued meanwhile; otherwise queues it.
    func send(_ message: [UInt8]) async {
        guard claimSending(message) else { return }
        await drain(message)
    }

    /// Whether the caller is now the sender, with `message` first. When another send is under way, `message` is queued behind it.
    func claimSending(_ message: [UInt8]) -> Bool {
        state.withLock { state in
            guard !state.closed else { return false }
            guard !state.sending else {
                state.outbox.append(message)
                return false
            }
            state.sending = true
            return true
        }
    }

    /// Sends `first`, then each queued message, until the queue is empty. A failed send ends the connection.
    func drain(_ first: [UInt8]) async {
        var next: [UInt8]? = first
        while let message = next {
            do { try await transport.send(message) } catch {
                shutdown()
                await transport.close()
                return
            }
            next = state.withLock { state in
                guard !state.closed, !state.outbox.isEmpty else {
                    state.sending = false
                    return nil
                }
                return state.outbox.removeFirst()
            }
        }
    }
}
