internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// Skills in the conversation: the `/` picker's list, and `/skill:name` (roadmap 0061, phase 3).
extension AgentConversation {
    /// The skills as picker rows: `skill:name`, with the description after a `skill` tag. The user's own and bundled ones are listed, as for the tool; a
    /// project's wait for project trust. Nothing is listed when skills are turned off.
    func skillCommands() async -> [SlashCommand] {
        let settings = current.withLock { $0.settings }
        let book = SkillBook(settings.configuration.skills.value, workingDirectory: settings.workspace)
        return book.catalog.skills.filter { $0.scope != .bundled }
            .map {
                SlashCommand(name: "skill:" + $0.name, summary: "skill · " + $0.description)
            }
    }

    /// What to send for `prompt`: itself, or, for `/skill:name request`, the request with the skill after it.
    /// - Returns: nil with a notice shown when the line asked for a skill that cannot be loaded; nothing is sent then.
    func expandingSkill(
        _ prompt: String, update: @Sendable (ConversationUpdate) -> Void
    ) -> String? {
        guard SkillInvocation.asksForSkill(prompt) else { return prompt }
        let settings = current.withLock { $0.settings }
        let book = SkillBook(settings.configuration.skills.value, workingDirectory: settings.workspace)
        switch SkillInvocation.expand(prompt, catalog: book.catalog, knownSources: book.knownSources) {
            case .prompt(let text): return text
            case .notASkill: return prompt
            case .failure(let reason):
                update(.notice(reason, isError: true))
                return nil
        }
    }
}
