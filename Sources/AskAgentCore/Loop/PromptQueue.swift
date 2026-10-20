internal import Synchronization

/// Input to one running agent. Producers may append concurrently; only the loop consumes it.
/// Messages leave the queue only after their user entries are persisted. A failed run leaves unsent messages here.
public final class PromptQueue: Sendable {
    private let pending = Mutex<[QueuedPrompt]>([])

    public init() {}

    /// Adds a message, in arrival order within its delivery class.
    public func append(_ prompt: QueuedPrompt) { pending.withLock { $0.append(prompt) } }

    /// Messages not yet persisted, in their original arrival order.
    public var remaining: [QueuedPrompt] { pending.withLock { $0 } }

    /// Records one steering message, or a follow-up when the run would otherwise finish.
    /// - Parameters:
    ///   - finished: whether the agent has finished its pending work.
    ///   - session: receives the user entry before the message leaves the queue.
    /// - Returns: the recorded message, or nil when none is eligible.
    /// - Throws: the persistence error; the message stays queued.
    func recordNext(finished: Bool, in session: SessionRecorder) throws(SessionFileError) -> QueuedPrompt? {
        let next: (Int, QueuedPrompt)? = pending.withLock { pending in
            let next =
                pending.firstIndex(where: { $0.delivery == .steering }) ?? (finished ? pending.indices.first : nil)
            return next.map { ($0, pending[$0]) }
        }
        guard let (index, prompt) = next else { return nil }
        // Only this loop removes messages; producers only append, so the index stays valid across I/O.
        // Do not hold the queue lock during a barrier flush or a damaged-session rewrite.
        try session.append(.user(prompt.text))
        pending.withLock { _ = $0.remove(at: index) }
        return prompt
    }
}
