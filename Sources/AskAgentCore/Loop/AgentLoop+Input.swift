extension AgentLoop {
    /// Acknowledges a queued message only after its user entry is persisted.
    func acceptInput(
        _ input: PromptQueue?, finished: Bool, atLimit: Bool, in session: SessionRecorder, events: (AgentEvent) -> Void
    ) throws(AgentError) -> Bool {
        if atLimit, input?.remaining.isEmpty == false { throw .turnLimit(settings.maximumTurns) }
        do {
            guard let prompt = try input?.recordNext(finished: finished, in: session) else { return false }
            events(.promptAccepted(prompt))
            return true
        } catch {
            throw .session(error)
        }
    }
}
