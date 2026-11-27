internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// Where another model starts answering (owner, 2026-11-27): a gray line before the first reply it writes, live and when the session is
/// shown again, in main and in a thread's lane. The session records the routing of each run, and a change shows where it was recorded.
extension AgentConversation {
    /// The line for `destination`, as the status line names a model: the model alone for Anthropic's, else connection/model.
    static func answersFromHere(_ destination: SessionDestination) -> ConversationUpdate {
        let label =
            destination.name == ProviderSettings.anthropic
            ? destination.model : "\(destination.name)/\(destination.model)"
        return .notice("\(label) answers from here.", isError: false)
    }

    /// Says so when `recorder`'s routing is no longer `before`, the one in force before this run selected its own; a first routing,
    /// with none before it, is not a change.
    static func noteModelChange(
        from before: SessionDestination?,
        in recorder: SessionRecorder,
        update: (ConversationUpdate) -> Void
    ) {
        guard let before, let now = recorder.destination, now != before else { return }
        update(answersFromHere(now))
    }

    /// Thread `name`'s run: the model that answers in its lane, on its status line (owner, 2026-11-26), recorded in its session as
    /// main's is, and a change told where it starts (owner, 2026-11-27).
    func routeThread(_ name: String, own: String?, update: @Sendable (ConversationUpdate) -> Void) async throws {
        guard let thread = threads.thread(name) else { return }
        let model = await threadResolvedModel(own)
        update(.thread(id: name, .label(model.label)))
        let before = thread.recorder.destination
        try thread.recorder.select(SessionRouting.destination(model), explicitlySelected: true)
        Self.noteModelChange(from: before, in: thread.recorder) { update(.thread(id: name, $0)) }
    }

    /// ``recorder()`` for a run, saying so when the run's model is not the one before it.
    func recorder(noting update: (ConversationUpdate) -> Void) throws -> SessionRecorder {
        let before = session.withLock { $0?.destination }
        let recorder = try recorder()
        Self.noteModelChange(from: before, in: recorder, update: update)
        return recorder
    }
}
