/// Hooks seeing the person's messages before they enter the conversation (roadmap 0192, ADR-0143): the run's first message and each
/// queued one. Rewrites chain in order, context joins after the message labelled by its hook, and the first block keeps it out.
extension AgentLoop {
    /// What the hooks made of a message.
    enum Submission: Equatable {
        /// Record and send `text`; `changedBy` names the hooks that rewrote it or added to it.
        case send(String, changedBy: [String])
        /// Keep it out, for `reason`.
        case blocked(String)
    }

    /// `text` through the hooks, in order.
    func submitting(_ text: String) async -> Submission {
        var sent = text
        var context: [String] = []
        var changedBy: [String] = []
        for hook in hooks {
            switch await hook.promptSubmit(sent) {
                case .allow: continue
                case .block(let reason): return .blocked("The hook \(hook.name) blocked this message: \(reason)")
                case .rewrite(let rewritten) where !rewritten.allSatisfy(\.isWhitespace):
                    sent = rewritten
                    changedBy.append(hook.name)
                case .context(let added) where !added.allSatisfy(\.isWhitespace):
                    context.append("[hook \(hook.name)] \(added)")
                    changedBy.append(hook.name)
                case .rewrite, .context: continue
            }
        }
        return .send(([sent] + context).joined(separator: "\n\n"), changedBy: changedBy)
    }

    /// Records the run's first message as the hooks leave it.
    /// - Throws: ``AgentError/promptBlocked(_:)`` when a hook keeps it out, before anything is recorded or sent.
    func recordFirst(_ prompt: String, in session: SessionRecorder, events: (AgentEvent) -> Void)
        async throws(AgentError)
    {
        switch await submitting(prompt) {
            case .blocked(let reason): throw .promptBlocked(reason)
            case .send(let text, let changedBy):
                try record(.user(text), in: session)
                if !changedBy.isEmpty { events(.hookChangedPrompt(hooks: changedBy)) }
        }
    }
}
