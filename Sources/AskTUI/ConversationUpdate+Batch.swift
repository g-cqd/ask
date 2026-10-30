extension ConversationUpdate {
    /// Whether this is a batch that clears the conversation, which ends the job outputs being watched as a clear does.
    var clears: Bool {
        if case .batch(let updates) = self { return updates.contains { $0 == .clearConversation || $0.clears } }
        return false
    }
}
