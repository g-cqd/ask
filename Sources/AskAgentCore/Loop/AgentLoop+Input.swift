extension AgentLoop {
    /// Lets the next queued message in, as the hooks leave it, and acknowledges it only after its user entry is persisted. One the hooks
    /// keep out leaves the queue unrecorded, and is said.
    func acceptInput(
        _ input: PromptQueue?,
        finished: Bool,
        atLimit: Bool,
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) -> Bool {
        if atLimit, input?.remaining.isEmpty == false { throw .turnLimit(settings.maximumTurns) }
        var blocked: (QueuedPrompt, String)?
        var changedBy: [String] = []
        do {
            let entered = try await input?
                .recordNext(finished: finished, in: session) { prompt in
                    switch await submitting(prompt.text) {
                        case .send(let text, let hooks):
                            changedBy = hooks
                            return text
                        case .blocked(let reason):
                            blocked = (prompt, reason)
                            return nil
                    }
                }
            if let (prompt, reason) = blocked { events(.promptBlocked(prompt, reason: reason)) }
            guard let entered else { return false }
            if !changedBy.isEmpty { events(.hookChangedPrompt(hooks: changedBy)) }
            events(.promptAccepted(entered))
            return true
        } catch {
            throw .session(error)
        }
    }
}
