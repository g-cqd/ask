internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The conversation's name (note n60; the owner's answers of 2026-11-11): from its first request, then from each compaction's summary,
/// by the model `threads.names` chooses, as a thread's (note n66): Apple's on-device model by default, which costs nothing; a provider's
/// with "model"; none with "numbered". Where none answers it stays unnamed, and the tab says the folder.
/// The name is kept in the session, titles the tab, and shows in the session lists.
extension AgentConversation {
    /// Names the conversation from its first request as a turn starts with `prompt`, unless it has a name or was tried already.
    func nameConversation(startingWith prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard let recorder = session.withLock({ $0 }),
            let source = ConversationNaming.source(in: recorder.tree, prompt: prompt),
            namingTried.withLock({ $0.insert(recorder.path).inserted })
        else { return }
        name(recorder, from: source, update: update)
    }

    /// Names the conversation again from what a compaction kept of it.
    func renameConversation(fromSummary summary: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard let recorder = session.withLock({ $0 }) else { return }
        name(recorder, from: summary, update: update)
    }

    private func name(
        _ recorder: SessionRecorder,
        from text: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) {
        let path = recorder.path
        // Held weakly while the name is asked for: a session switched away from is let go at once, its writer lock with it (the PTY
        // sweep's probe-interactive N, 2026-11-13), and is not this one's to name.
        Task { [weak recorder] in
            guard let name = await chosenName(for: text),
                let recorder,
                session.withLock({ $0?.path }) == path
            else { return }
            try? recorder.recordThread(.renamed(ThreadRecord.conversation, to: name))
            update(.conversationName(name))
        }
    }
}
