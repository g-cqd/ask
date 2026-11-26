extension AgentLoop {
    /// Lets every queued message the run may take in at once (owner, 2026-11-26): all steering, and at the end of the work the
    /// follow-ups too, so no model turn comes between them; consecutive user entries are one message to the model
    /// (``RequestContext``). Each is acknowledged only after its user entry is persisted; one the hooks keep out leaves the queue
    /// unrecorded, and is said.
    /// - Returns: whether any came in.
    func acceptInput(
        _ input: PromptQueue?,
        finished: Bool,
        atLimit: Bool,
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) -> Bool {
        if atLimit, input?.remaining.isEmpty == false { throw .turnLimit(settings.maximumTurns) }
        var any = false
        // Bounded by what is queued: each pass takes one message out, recorded or kept out.
        for _ in 0 ..< (input?.remaining.count ?? 0) {
            switch try await acceptOne(input, finished: finished, in: session, events: events) {
                case .entered: any = true
                case .keptOut: continue
                case .none: return any
            }
        }
        return any
    }

    private enum Taken { case entered, keptOut, none }

    /// The next queued message, as the hooks leave it.
    private func acceptOne(
        _ input: PromptQueue?,
        finished: Bool,
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) -> Taken {
        var blocked: (QueuedPrompt, String)?
        var changedBy: [String] = []
        var timedOut: [String] = []
        do {
            let entered = try await input?
                .recordNext(finished: finished, in: session) { prompt in
                    switch await submitting(prompt.text) {
                        case .send(let text, let hooks, let expired):
                            changedBy = hooks
                            timedOut = expired
                            return text
                        case .blocked(let reason, let expired):
                            blocked = (prompt, reason)
                            timedOut = expired
                            return nil
                    }
                }
            for name in timedOut { events(.hookTimedOut(hook: name, point: "prompt.submit")) }
            if let (prompt, reason) = blocked { events(.promptBlocked(prompt, reason: reason)) }
            guard let entered else { return blocked == nil ? .none : .keptOut }
            if !changedBy.isEmpty { events(.hookChangedPrompt(hooks: changedBy)) }
            events(.promptAccepted(entered))
            return .entered
        } catch {
            throw .session(error)
        }
    }
}
