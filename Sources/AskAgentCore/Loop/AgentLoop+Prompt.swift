internal import AskAI

/// Hooks seeing the person's messages before they enter the conversation (roadmap 0192, ADR-0143): the run's first message and each
/// queued one. Rewrites chain in order, context joins after the message labelled by its hook, and the first block keeps it out.
extension AgentLoop {
    /// What the hooks made of a message.
    enum Submission: Equatable {
        /// Record and send `text`; `changedBy` names the hooks that rewrote it or added to it.
        case send(String, changedBy: [String], timedOut: [String])
        /// Keep it out, for `reason`.
        case blocked(String, timedOut: [String])
    }

    /// `text` through the hooks, in order.
    func submitting(_ text: String) async -> Submission {
        var sent = text
        var context: [String] = []
        var changedBy: [String] = []
        var timedOut: [String] = []
        for hook in hooks {
            let current = sent
            let fallback: PromptSubmitDecision = hook.failureMode == .closed ? .block("timed out") : .allow
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let note: (AgentEvent) -> Void = { _ in timedOut.append(hook.name) }
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let decision = await HookDeadline.ask(
                hook,
                at: "prompt.submit",
                clock: clock,
                orElse: fallback,
                timedOut: note
            ) { await hook.promptSubmit(current) }
            switch decision {
                case .allow: continue
                case .block(let reason):
                    return .blocked("The hook \(hook.name) blocked this message: \(reason)", timedOut: timedOut)
                case .rewrite(let rewritten) where !rewritten.allSatisfy(\.isWhitespace):
                    sent = rewritten
                    changedBy.append(hook.name)
                case .context(let added) where !added.allSatisfy(\.isWhitespace):
                    context.append("[hook \(hook.name)] \(added)")
                    changedBy.append(hook.name)
                case .rewrite, .context: continue
            }
        }
        return .send(([sent] + context).joined(separator: "\n\n"), changedBy: changedBy, timedOut: timedOut)
    }

    /// Records the run's first message as the hooks leave it.
    /// - Throws: ``AgentError/promptBlocked(_:)`` when a hook keeps it out, before anything is recorded or sent.
    func recordFirst(
        _ prompt: String,
        images: [ImagePart] = [],
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    )
        async throws(AgentError)
    {
        switch await submitting(prompt) {
            case .blocked(let reason, let timedOut):
                for name in timedOut { events(.hookTimedOut(hook: name, point: "prompt.submit")) }
                throw .promptBlocked(reason)
            case .send(let text, let changedBy, let timedOut):
                for name in timedOut { events(.hookTimedOut(hook: name, point: "prompt.submit")) }
                // Hooks see the text; the pictures pasted with it pass as they are (roadmap 0224).
                try record(.user(text, images: images), in: session)
                if !changedBy.isEmpty { events(.hookChangedPrompt(hooks: changedBy)) }
        }
    }
}
