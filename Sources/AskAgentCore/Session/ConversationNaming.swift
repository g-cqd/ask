/// When the conversation is named (note n60; the owner's answers of 2026-11-11): from its first request while it has no name, and
/// again from each compaction's summary, which the caller names from as it comes.
public enum ConversationNaming {
    /// What to name the conversation in `tree` from as a turn starts with `prompt`: its first request, which is `prompt` for a new
    /// one; nil once it has a name, or when there is no request of the person's to name it from.
    public static func source(in tree: SessionTree, prompt: String) -> String? {
        guard tree.conversationName == nil else { return nil }
        let first = SessionSummary(tree).firstPrompt ?? prompt
        guard first != AgentLoop.continuationPrompt, first != AgentLoop.reconnectionPrompt,
            first.contains(where: { !$0.isWhitespace })
        else { return nil }
        return first
    }
}
