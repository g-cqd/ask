internal import AskTUI
internal import Synchronization

/// `#123` in a message (roadmap 0186).
extension AgentConversation {
    /// `text` with the pull requests and issues it names attached; the screen is told which resolved, to draw them as tokens.
    func attachingForgeReferences(_ text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async
        -> String
    {
        await ForgeAttachment.attach(text, workspace: current.withLock { $0.settings.workspace }) {
            update(.referencesResolved($0))
        }
    }
}
