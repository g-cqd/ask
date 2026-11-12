public import AskAI

extension AgentLoop {
    /// Runs `prompt` to completion in `session`, reporting each step to `events`.
    /// Queued steering enters after a response and all its tool results; follow-ups enter only when the run
    /// would finish. One message enters per boundary, with steering first. Unsent input remains queued on failure.
    /// - Parameters:
    ///   - prompt: the initial user message.
    ///   - images: the pictures pasted into it (roadmap 0224).
    ///   - session: where completed work is persisted.
    ///   - input: messages queued while this run is in flight; nil for a run without interactive input.
    ///   - events: completed steps, including acknowledgments of persisted queued messages.
    /// - Throws: an ``AgentError``. Cancelling the task aborts the run as ``AgentError/cancelled``.
    public func run(
        _ prompt: String,
        images: [ImagePart] = [],
        in session: SessionRecorder,
        input: PromptQueue? = nil,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        var loop = self
        loop.stopMark = session.tree.entries.count
        try await loop.drive(prompt, images: images, in: session, input: input, events: events)
    }
}
