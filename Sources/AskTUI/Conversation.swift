internal import TerminalKitCodecs
internal import TerminalKitInput

/// Starts runs for the screen. Implemented by the composition root over the agent loop, so AskTUI never
/// imports the agent (ADR-0009).
public protocol Conversation: Sendable {
    /// Starts a run for `prompt`. Updates arrive through `update`, ending with ``ConversationUpdate/runEnded``.
    /// - Returns: the run's task; cancelling it aborts the run.
    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>

    /// Offers input to the current run. A persisted message is acknowledged by ``ConversationUpdate/promptAccepted(id:text:)``.
    /// Until then the screen owns a copy, which it starts after normal completion or restores on failure.
    func enqueue(_ text: String, id: Int, followUp: Bool)

    /// The user's answer to the question ``ConversationUpdate/askApproval(id:question:)`` asked.
    func answer(approval id: Int, with choice: ApprovalChoice)

    /// The commands this conversation understands, beyond the screen's own `/help` and `/quit`.
    var commands: [SlashCommand] { get }

    /// Starts anything that reports on its own while the screen is open, such as a new build appearing, until the
    /// returned task is cancelled. Nil when there is nothing to watch.
    func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>?

    /// Runs the command `name`, one of ``commands``. It is a run like a prompt's: updates arrive through
    /// `update`, ending with ``ConversationUpdate/runEnded``, and cancelling the task aborts it.
    func command(
        _ name: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never>
}

extension Conversation {
    /// No in-flight input; the screen starts unacknowledged messages after the current run ends.
    public func enqueue(_ text: String, id: Int, followUp: Bool) {}

    /// Never asks, so never answered.
    public func answer(approval id: Int, with choice: ApprovalChoice) {}

    /// No commands of its own.
    public var commands: [SlashCommand] { [] }

    /// Nothing to watch.
    public func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>? { nil }

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
