internal import AskAgentCore
internal import AskTUI
internal import Synchronization

extension AgentConversation {
    /// After a compaction, a line comparing what the work it summarised cost with the stretch before it (roadmap 0239; the owner,
    /// 2026-11-22: "a comparison between two compactions"). Its time is the time worked, the model's and the tools'; the person's own
    /// between turns is left out. Nothing when the stretch spent nothing.
    func sayCompactionSpend(update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard let tree = session.withLock({ $0?.tree }) else { return }
        let stretches = WorkSpend.compactionStretches(in: tree)
        guard let last = stretches.last, !last.isEmpty else { return }
        let said = { (spend: WorkSpend) -> String in
            var worked = spend
            worked.wallMilliseconds = spend.workingMilliseconds
            return TurnSpend(worked).summary(localized: false)
        }
        guard stretches.count > 1, case let before = stretches[stretches.count - 2], !before.isEmpty else {
            update(.notice("Worked before this compaction: \(said(last))", isError: false))
            return
        }
        update(
            .notice(
                "Worked since the previous compaction: \(said(last)); the stretch before: \(said(before))",
                isError: false
            )
        )
    }
}
