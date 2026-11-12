internal import Synchronization

/// `#123` in a message (roadmap 0186).
extension AgentConversation {
    /// `text` with the pull requests and issues it names attached.
    func attachingForgeReferences(_ text: String) async -> String {
        await ForgeAttachment.attach(text, workspace: current.withLock { $0.settings.workspace })
    }
}
