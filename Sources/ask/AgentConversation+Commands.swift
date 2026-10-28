internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// The commands the screen offers beyond its own `/help` and `/quit`.
extension AgentConversation {
    var commands: [SlashCommand] {
        // @dl:accept -- a table of command names and summaries; the entries are the data, and they read alike because every command has a name and a sentence
        // @dl:accept -- a table of command names and summaries; the entries are the data, and they read alike because every command has a name and a sentence
        // @dl:accept -- screen and conversation command tables match only because tables of data read alike
        [
            // @dl:accept -- this table's head matches the built-in table's head; the entries are the data
            SlashCommand(
                name: "config",
                summary: "Edit settings interactively, or /config now to read and show every setting and its source.",
                takesChoices: true, category: .configuration),
            SlashCommand(name: "compact", summary: "Summarise the conversation now, keeping the recent messages."),
            SlashCommand(name: "new", summary: "Start a new session; the previous session stays saved."),
            SlashCommand(
                name: "model",
                summary: "Choose a model from every account you are signed in to, or /model [PROVIDER] MODEL, --reset.",
                takesChoices: true, category: .model),
            SlashCommand(
                name: "thinking",
                summary: "Choose how hard the model thinks: the efforts it takes, or /thinking LEVEL.",
                takesChoices: true, category: .model),
            SlashCommand(
                name: "login",
                summary: "Sign in to a provider with an account or an API key, without leaving: /login PROVIDER.",
                takesChoices: true, category: .model),
            SlashCommand(
                name: "logout", summary: "Sign out of one account, or /logout all, without leaving.",
                takesChoices: true,
                category: .model
            ),
            // @dl:accept -- a resume entry belongs to both command tables; the conversation's sentence names its own arguments
            // @dl:accept -- a resume entry beside the screen's built-ins shares a table's shape; the sentences are the data
            SlashCommand(
                name: "resume", summary: "Choose a session, or /resume NAME, PREFIX or PATH.", takesChoices: true),
            // @dl:accept -- the conversation's list reads alike entry to entry because every entry is a name and a sentence
            // @dl:accept -- a tree entry beside the screen's follow-up shares a command table's shape; the sentences are the data
            SlashCommand(
                name: "tree", summary: "Choose a prompt to go back to before it, or /tree N.", takesChoices: true),
            SlashCommand(
                name: "fork",
                summary: "Continue in a new session: /fork, or /fork N from before prompt N. The original stays."),
            SlashCommand(
                name: "mcp", summary: "Show the MCP servers: which are connected and how many tools each offers.",
                category: .tools),
            SlashCommand(
                name: "reload", summary: "Switch to a newly built ask, keeping this session. /reload now stops jobs.",
                category: .tools)
        ]
    }

    func command(
        _ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        Task {
            switch name {
                case "config":
                    let scope = arguments.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if scope == "user" || scope == "project" {
                        await self.openConfigEditor(ConfigEditor.Scope(rawValue: scope) ?? .user, update: update)
                    } else {
                        await self.showConfiguration(update: update)
                    }
                case "compact":
                    self.keepAwake.turnStarted()
                    await self.compact(update: update)
                    self.keepAwake.turnEnded()
                case "new": await self.newSession(arguments: arguments, update: update)
                case "resume": await self.resumeSession(arguments: arguments, update: update)
                case "tree": self.tree(arguments: arguments, update: update)
                case "fork": await self.forkSession(arguments: arguments, update: update)
                case "model": await self.model(arguments: arguments, update: update)
                case "thinking": await self.thinking(arguments: arguments, update: update)
                case "login": await self.login(arguments: arguments, update: update)
                case "logout": await self.logout(arguments: arguments, update: update)
                case "mcp": update(.notice(MCPHub.report(self.mcp.status).joined(separator: "\n"), isError: false))
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
        update(.notice(lines.joined(separator: "\n"), isError: false))
    }

    /// Compacts at the user's request, whatever the context's size. Nothing is made up: with nothing recorded, or
    /// nothing before the recent messages, it says so.
    private func compact(update: @Sendable (ConversationUpdate) -> Void) async {
        guard recordedSession(orSay: "Nothing to compact yet.", update: update) != nil else { return }
        do {
            await refreshSettings(update: update)
            let checked = try self.recorder()
            try await agentLoop().compactNow(in: checked) { self.deliver($0, to: update) }
        } catch {
            report(error, to: update)
        }
    }
}
