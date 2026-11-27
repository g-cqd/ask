internal import AskTUI
internal import AskTools

/// The model is told when a job it left running ends (owner, 2026-11-27), so it can go on with something else instead of waiting,
/// and picks the end up even after its turn is over.
extension AgentConversation {
    /// Gives `ending` to the conversation the job was started for: a thread still open, else main. Sent as the next message, it
    /// starts a turn when none runs, or goes in at the running turn's next step.
    func deliver(_ ending: JobEnding, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        if let owner = ending.owner, let thread = threads.thread(owner), thread.state != .merged,
            thread.state != .merging
        {
            sendToThread(owner, text: ending.report, update: update)
            return
        }
        update(.submitPrompt(ending.report))
    }
}
