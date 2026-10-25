internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// Skills in the conversation: the `/` picker's list, and `/skill:name` (roadmap 0061, phase 3).
extension AgentConversation {
    /// The skills as picker rows: `skill:name`, with a tag and the description. The user's and a trusted project's are listed as the tool offers them; a
    /// project's that waits for trust is listed too, saying so, so that choosing it explains instead of the skill seeming not to exist. Bundled ones
    /// need `--from bundled`. Nothing is listed when skills are turned off.
    func skillCommands() async -> [SlashCommand] {
        let settings = current.withLock { $0.settings }
        let book = SkillBook(settings.configuration.skills.value, workingDirectory: settings.workspace)
        let loaded = book.catalog.skills.filter { $0.scope != .bundled }
            .map {
                SlashCommand(
                    name: "skill:" + $0.name,
                    summary: ($0.scope == .project ? "project skill · " : "skill · ") + $0.description)
            }
        let waiting = book.catalog.untrusted.map {
            SlashCommand(
                name: "skill:" + $0.skill.name,
                summary: "project skill, not trusted · look at it, then ask trust --skills in a terminal")
        }
        return loaded + waiting
    }

    /// Tells the user, once, that a project's skills were found and are not loaded. The first prompt is when skills are first looked for, so that is when
    /// they are told.
    func noticeUntrustedSkills(update: @Sendable (ConversationUpdate) -> Void) {
        guard
            !skillNoticeGiven.withLock({ given in
                defer { given = true }
                return given
            })
        else { return }
        let settings = current.withLock { $0.settings }
        let count = SkillBook(settings.configuration.skills.value, workingDirectory: settings.workspace).catalog
            .untrusted.count
        guard count > 0 else { return }
        update(
            .notice(
                "\(count) project skill\(count == 1 ? " is" : "s are") not loaded: not trusted as \(count == 1 ? "it is" : "they are") now. ask skills lists \(count == 1 ? "it" : "them"); ask trust --skills, in a terminal, trusts what you have read.",
                isError: false))
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
