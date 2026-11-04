internal import AskAI

/// Hooks asked when a run would end (roadmap 0192, ADR-0143): a `continue` is recorded as a labelled user entry and the run goes on.
extension AgentLoop {
    /// Asks the hooks whether the run that `response` would end goes on, after the person's follow-ups were let in.
    /// - Parameters:
    ///   - response: the reply that would end the run.
    ///   - atLimit: whether the next request would pass the turn limit, which continues count against.
    ///   - session: where a continue's message is recorded.
    ///   - events: where the continue, or the limit that kept hooks from being asked, is said.
    /// - Returns: whether a hook continued the run; its message is recorded.
    /// - Throws: ``AgentError/session(_:)`` when the message cannot be recorded.
    mutating func continuesByHook(
        _ response: AssembledResponse,
        atLimit: Bool,
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) -> Bool {
        guard !hooks.isEmpty else { return false }
        guard hookContinues < settings.maximumHookContinues else {
            events(.hookContinuesStopped(.continues(settings.maximumHookContinues)))
            return false
        }
        guard !atLimit else {
            events(.hookContinuesStopped(.turns(settings.maximumTurns)))
            return false
        }
        let stop = RunStop(
            response: response,
            continued: hookContinues,
            changed: Self.changesThings(session.tree.entries.dropFirst(stopMark))
        )
        stopMark = session.tree.entries.count
        // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
        var messages: [String] = []
        for hook in hooks {
            let decision = await HookDeadline.ask(hook, at: "run.stop", clock: clock, orElse: .stop, timedOut: events) {
                await hook.runStop(stop)
            }
            guard case .continue(let message) = decision,
                !message.allSatisfy(\.isWhitespace)
            else { continue }
            messages.append("[hook \(hook.name)] \(message)")
        }
        guard !messages.isEmpty else { return false }
        let text = messages.joined(separator: "\n\n")
        try record(.user(text), in: session)
        hookContinues += 1
        events(.hookContinued(text))
        return true
    }

    /// Whether `entries` hold a response that made a call that changes things.
    static func changesThings(_ entries: some Sequence<SessionEntry>) -> Bool {
        entries.contains { entry in
            guard case .response(let response, _) = entry.payload else { return false }
            return toolCalls(in: response).contains { ApprovalPolicy.changesThings($0.name, $0.input) }
        }
    }
}
