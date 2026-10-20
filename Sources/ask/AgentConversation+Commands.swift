internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The commands the screen offers beyond its own `/help` and `/quit`.
extension AgentConversation {
    var commands: [SlashCommand] {
        [
            SlashCommand(
                name: "config", summary: "Read the configuration again and show every setting and its source."),
            SlashCommand(name: "compact", summary: "Summarise the conversation now, keeping the recent messages."),
            SlashCommand(name: "new", summary: "Start a new session; the previous session stays saved."),
            SlashCommand(
                name: "reload", summary: "Switch to a newly built ask, keeping this session. /reload now stops jobs.")
        ]
    }

    func command(
        _ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        Task {
            switch name {
                case "config": await self.showConfiguration(update: update)
                case "compact": await self.compact(update: update)
                case "new": self.newSession(arguments: arguments, update: update)
                case "reload": await self.reload(arguments: arguments, update: update)
                default: update(.notice("There is no command /\(name).", isError: true))
            }
            update(.runEnded)
        }
    }

    /// Reads the configuration again, so a change is announced here as it would be before a prompt, then shows it.
    private func showConfiguration(update: @Sendable (ConversationUpdate) -> Void) async {
        await refreshSettings(update: update)
        let settings = current.withLock { $0.settings }
        let lines = settings.report(userFile: source.loader.userPath, projectFile: source.loader.projectPath)
        for line in lines { update(.notice(line, isError: false)) }
    }

    /// Compacts at the user's request, whatever the context's size. Nothing is made up: with nothing recorded, or
    /// nothing before the recent messages, it says so.
    private func compact(update: @Sendable (ConversationUpdate) -> Void) async {
        guard let recorder = session.withLock({ $0 }), !recorder.tree.entries.isEmpty else {
            update(.notice("Nothing to compact yet.", isError: false))
            return
        }
        do {
            await refreshSettings(update: update)
            try await agentLoop().compactNow(in: recorder) { self.deliver($0, to: update) }
        } catch {
            report(error, to: update)
        }
    }
}
