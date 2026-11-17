internal import AskAgentCore
internal import AskTUI
internal import Synchronization

extension AgentConversation {
    /// What the screen shows first for a resumed session: its conversation, then its usage so far, which the
    /// status line keeps adding to.
    ///
    /// The conversation is what a request still reads, from the last compaction's first kept entry on, with a line saying how much
    /// came before (roadmap 0238): showing a long session whole took seconds and 150 MB the screen then kept.
    /// - Parameter whole: show every entry, for a client that is sent the whole of what the session holds.
    /// - Returns: the updates that draw the conversation, then its usage and context.
    func history(whole: Bool = false) -> [ConversationUpdate] {
        guard let tree = session.withLock({ $0?.tree }) else { return [contextUpdate()] }
        let shown = whole ? (entries: tree.activeBranch(), earlier: 0) : tree.sinceLastCompaction()
        // With its threads' blocks where they started and merged (roadmap 0195).
        let branch = shown.entries
        let updates = replayed(branch, after: nil, placing: Self.threadBlocks(tree.threads, under: nil, on: branch))
        var notice: [ConversationUpdate] = []
        if shown.earlier > 0 {
            notice = [
                .notice(
                    "Showing this conversation since its last compaction; \(shown.earlier) earlier entries stay in the session. "
                        + "/search finds them and /rewind goes back to any prompt.",
                    isError: false
                )
            ]
        }
        return notice + updates + [.status(usage.withLock { $0.compact }), contextUpdate()]
    }
}
