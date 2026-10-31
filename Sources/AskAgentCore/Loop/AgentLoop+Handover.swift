internal import AskAI

/// How a running turn takes a change made while it runs (roadmap 0113, ``LoopHandover``).
extension AgentLoop {
    /// This loop with `handover`, where a change made while one of its turns runs is offered.
    public func handing(over handover: LoopHandover) -> AgentLoop {
        var loop = self
        loop.handover = handover
        return loop
    }

    /// This turn continued with `newer`'s model, tools and settings. What the turn learned stays: the repairs already said, the drops
    /// counted, and the window when the model is the same; another model's window is its own.
    func adopting(_ newer: AgentLoop) -> AgentLoop {
        var adopted = self
        adopted.provider = newer.provider
        adopted.tools = newer.tools
        adopted.context = newer.context
        adopted.hooks = newer.hooks
        adopted.retry = newer.retry
        if newer.settings.model != settings.model { adopted.learnedWindow = newer.learnedWindow }
        adopted.settings = newer.settings
        return adopted
    }

    /// Takes the loop offered since the last request, when there is one.
    mutating func takeOffered() {
        guard let newer = handover?.take() else { return }
        self = adopting(newer)
    }

    /// Waits `delay` before a retry, or less when a change is offered meanwhile, so the retry goes to the new loop at once.
    /// - Returns: whether a change is waiting to be taken.
    /// - Throws: ``AgentError/cancelled`` when the turn is stopped while waiting.
    func pause(for delay: Duration, handsOver: Bool) async throws(AgentError) -> Bool {
        let clock = clock
        guard handsOver, let handover else {
            do { try await clock.sleep(for: delay) } catch { throw .cancelled }
            return false
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await clock.sleep(for: delay) }
            group.addTask { await handover.offered() }
            await group.next()
            group.cancelAll()
        }
        guard !Task.isCancelled else { throw .cancelled }
        return handover.isPending
    }
}
