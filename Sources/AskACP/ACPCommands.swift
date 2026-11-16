internal import AemiJSON
internal import AskTUI

/// The commands a client can run (ACP v1, Slash Commands): the client is told them once the session exists, and a prompt that
/// is one of them, typed as on the screen (`/tasks all`), runs it and is answered when it ends. Any other prompt that starts
/// with a slash is the model's, as it was typed: a path, or a command of the client's own.
enum ACPCommands {
    /// A command as it was typed.
    struct Typed: Sendable, Equatable {
        let name: String
        let arguments: String
    }

    /// The commands served, of those a conversation has: the ones whose answer is words and which leave the session the one
    /// its id names. The others need the screen (a list to choose from, a lane, an editor), a line typed for a secret, which
    /// no form may ask, or change which session this is.
    static let served: Set<String> = ["compact", "tasks"]

    /// The command `text` is, when it is one `conversation` has and this serves.
    static func typed(_ text: String, in conversation: any Conversation) -> Typed? {
        guard case .command(let name, let arguments) = SlashInput(text), served.contains(name),
            conversation.commands.contains(where: { $0.name == name })
        else { return nil }
        return Typed(name: name, arguments: arguments)
    }

    /// What the model is sent for the prompt `text`: itself, or with one slash fewer where two kept it from being a command,
    /// as on the screen (`//tasks` is sent as `/tasks`).
    static func prompt(_ text: String, in conversation: any Conversation) -> String {
        guard text.hasPrefix("//"), typed(String(text.dropFirst()), in: conversation) != nil else { return text }
        return String(text.dropFirst())
    }

    /// `available_commands_update`: the commands served and the skills, which a prompt names as `/skill:name request`; nil when
    /// there is none to tell.
    static func update(for conversation: any Conversation) async -> JSONValue? {
        var commands: [JSONValue] = conversation.commands.filter { served.contains($0.name) }
            .map {
                ["name": .string($0.name), "description": .string($0.summary)]
            }
        for skill in await conversation.skillCommands() {
            commands.append(
                [
                    "name": .string(skill.name), "description": .string(skill.summary),
                    "input": ["hint": "what to do with it"]
                ]
            )
        }
        guard !commands.isEmpty else { return nil }
        return ["sessionUpdate": "available_commands_update", "availableCommands": .array(commands)]
    }

    /// What a command said, as its answer: a piece of the agent's message, a line of its own.
    static func answer(_ text: String) -> JSONValue {
        ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": .string(text + "\n")]]
    }
}
