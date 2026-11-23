internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Synchronization

extension AgentConversation {
    /// `text` after a note naming the skills the person trusted since the last message, which the `skill` tool now loads: the
    /// list at the start of the session is left as it was, so the conversation's prompt cache holds. Nothing when the trust
    /// store has not changed, or the change trusted nothing new; the person is told which reached the model.
    func attachingNewlyTrustedSkills(_ text: String, update: @Sendable (ConversationUpdate) -> Void) -> String {
        let trustPath = source.loader.trustPath
        guard skillTrust.trustChanged(at: trustPath) else { return text }
        let settings = current.withLock { $0.settings }
        let book = SkillBook(settings.configuration, workingDirectory: settings.workspace, trustPath: trustPath)
        let served = Set(skillTrust.shelf.catalog.skills.map(\.name))
        skillTrust.shelf.replace(book.catalog, knownSources: book.knownSources)
        let fresh = book.catalog.skills.filter {
            !served.contains($0.name) && $0.modelInvocable && $0.scope != .bundled
        }
        guard !fresh.isEmpty else { return text }
        // A session that began with no skill had no `skill` tool: it joins now. One that had it keeps it, which this one would
        // only shadow.
        mcp.live.replace(group: SkillShelf.liveGroup, with: [SkillTool(shelf: skillTrust.shelf)])
        let names = fresh.map(\.name).joined(separator: ", ")
        update(.notice("Trusted since the last message, now offered to the model: \(names).", isError: false))
        let lines = fresh.map(\.advertisement).joined(separator: "\n")
        return
            "Skills the user trusted during this session, which the skill tool now loads by name:\n\(lines)\n\n\(text)"
    }
}
