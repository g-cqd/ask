internal import TerminalKitCodecs
internal import TerminalKitInput

/// Starts runs for the screen. Implemented by the composition root over the agent loop, so AskTUI never
/// imports the agent (ADR-0009).
public protocol Conversation: Sendable {
    /// Starts a run for `prompt`. Updates arrive through `update`, ending with ``ConversationUpdate/runEnded``.
    /// - Returns: the run's task; cancelling it aborts the run.
    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>

    /// The commands this conversation understands, beyond the screen's own `/help` and `/quit`.
    var commands: [SlashCommand] { get }

    /// Runs the command `name`, one of ``commands``. It is a run like a prompt's: updates arrive through
    /// `update`, ending with ``ConversationUpdate/runEnded``, and cancelling the task aborts it.
    func command(
        _ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never>
}

extension Conversation {
    /// No commands of its own.
    public var commands: [SlashCommand] { [] }

    /// Ends at once, saying the command is unknown. A conversation with no commands is never asked to run one.
    public func command(
        _ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        Task {
            update(.notice("There is no command /\(name).", isError: true))
            update(.runEnded)
        }
    }
}
