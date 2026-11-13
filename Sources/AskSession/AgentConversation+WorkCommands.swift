internal import AskTUI

/// Commands that keep the work going beside the person (roadmaps 0227, 0228, t209): a goal, recurring prompts, search.
extension AgentConversation {
    var workCommands: [SlashCommand] {
        // @dl:accept -- a table of command names and summaries; a test's table reads alike because every entry is a name and a sentence
        [
            SlashCommand(
                name: "goal",
                summary:
                    "Work until a condition holds, judged after each run: /goal CONDITION, /goal to see it, /goal clear.",
                duringTurn: .atOnce
            ),
            SlashCommand(
                name: "loop",
                summary:
                    "Send a prompt on a schedule: /loop 10m TASK, /loop to list, /loop stop N. Skipped while a turn runs.",
                duringTurn: .atOnce
            ),
            SlashCommand(
                name: "search",
                summary:
                    "Search this session's whole history: /search cache key. Typos and parts of identifiers match.",
                duringTurn: .atOnce
            )
        ]
    }

    /// Runs `name` when it is one of these; false when it is not.
    func workCommand(_ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async
        -> Bool
    {
        switch name {
            case "goal": goalCommand(arguments, update: update)
            case "loop": loopCommand(arguments, update: update)
            case "search": update(.notice(await SessionSearchCommand.answer(to: arguments, in: self), isError: false))
            default: return false
        }
        return true
    }
}
