internal import AskAgentCore
internal import AskTUI

extension AgentConversation {
    /// What the turn that began after `start` cost, on the status line until the next one (roadmap 0239); nothing when it spent nothing.
    func showTurnSpend(
        in recorder: SessionRecorder,
        since start: EntryID?,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) {
        let spend = WorkSpend.since(start, in: recorder.tree)
        guard !spend.isEmpty else { return }
        update(.turnSpent(TurnSpend(spend)))
    }
}
