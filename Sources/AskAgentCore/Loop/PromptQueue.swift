internal import Synchronization

/// Input to one running agent. Producers may append concurrently; only the loop consumes it.
/// Messages leave the queue only after their user entries are persisted. A failed run leaves unsent messages here.
public final class PromptQueue: Sendable {
    private struct State {
        var pending: [QueuedPrompt] = []
        /// The message the loop is recording, which can no longer be withdrawn (roadmap 0174).
        var recording: Int?
    }

    private let state = Mutex(State())

    public init() {}

    /// Adds a message, in arrival order within its delivery class.
    public func append(_ prompt: QueuedPrompt) { state.withLock { $0.pending.append(prompt) } }

    /// Messages not yet persisted, in their original arrival order.
    public var remaining: [QueuedPrompt] { state.withLock { $0.pending } }

    /// Takes back message `id`, so it is never sent (roadmap 0174).
    /// - Returns: false when it is not queued, or the loop is already recording it.
    public func withdraw(id: Int) -> Bool {
        state.withLock { state in
            guard state.recording != id, let index = state.pending.firstIndex(where: { $0.id == id }) else {
                return false
            }
            state.pending.remove(at: index)
            return true
        }
    }

    /// Records one steering message, or a follow-up when the run would otherwise finish.
    /// - Parameters:
    ///   - finished: whether the agent has finished its pending work.
    ///   - session: receives the user entry before the message leaves the queue.
    /// - Returns: the recorded message, or nil when none is eligible.
    /// - Throws: the persistence error; the message stays queued.
    func recordNext(finished: Bool, in session: SessionRecorder) throws(SessionFileError) -> QueuedPrompt? {
        let next: QueuedPrompt? = state.withLock { state in
            let index =
                state.pending.firstIndex(where: { $0.delivery == .steering })
                ?? (finished ? state.pending.indices.first : nil)
            guard let index else { return nil }
            state.recording = state.pending[index].id
            return state.pending[index]
        }
        guard let prompt = next else { return nil }
        // Do not hold the queue lock during a barrier flush or a damaged-session rewrite. The message is marked as being recorded,
        // so a withdrawal meanwhile refuses it; others may come and go, so it leaves the queue by its id.
        defer { state.withLock { $0.recording = nil } }
        try session.append(.user(prompt.text))
        state.withLock { state in state.pending.removeAll { $0.id == prompt.id } }
        return prompt
    }
}
