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
    /// What a message becomes when the loop takes it, before the hooks see it: `@server:uri` read and attached (roadmap 0067), which
    /// needs the network and so cannot be done as it is typed.
    private let prepare: @Sendable (String) async -> String

    /// A queue whose messages are prepared by `prepare` when the loop takes them; by default they go as they are.
    public init(prepare: @escaping @Sendable (String) async -> String = { $0 }) { self.prepare = prepare }

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
    ///   - admit: what the hooks make of the message once prepared (roadmap 0192): the text to record, or nil to keep it out.
    /// - Returns: the recorded message, as recorded, or nil when none is eligible or `admit` kept it out (it leaves the queue then).
    /// - Throws: the persistence error; the message stays queued.
    func recordNext(
        finished: Bool,
        in session: SessionRecorder,
        admit: (QueuedPrompt) async -> String? = { $0.text }
    ) async throws(SessionFileError) -> QueuedPrompt? {
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
        // Prepared, then what the hooks make of it (roadmap 0192): nil keeps it out, and it leaves the queue unrecorded.
        let ready = QueuedPrompt(id: prompt.id, text: await prepare(prompt.text), delivery: prompt.delivery)
        guard let text = await admit(ready) else {
            state.withLock { state in state.pending.removeAll { $0.id == prompt.id } }
            return nil
        }
        try session.append(.user(text))
        state.withLock { state in state.pending.removeAll { $0.id == prompt.id } }
        return QueuedPrompt(id: prompt.id, text: text, delivery: prompt.delivery)
    }
}
