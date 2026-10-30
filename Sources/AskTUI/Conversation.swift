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
    /// The person's answers to the questions ``ConversationUpdate/askQuestions(id:questions:)`` asked, or nil when they declined.
    func answer(questions id: Int, with answers: [QuestionAnswer]?)

    /// The commands this conversation understands, beyond the screen's own `/help` and `/quit`.
    var commands: [SlashCommand] { get }

    /// The project's files, listed for the `@` picker: relative to the working directory, only what ask may read, bounded. Asked for when
    /// an `@` first appears and again once the listing is old, off the input path.
    func projectFiles() async -> ProjectFiles

    /// The skills the `/` picker offers, as commands named `skill:name` with their descriptions. Asked for once, when the picker first opens.
    func skillCommands() async -> [SlashCommand]

    /// What `/command ` offers to choose from, for a command that ``SlashCommand/takesChoices``: the models, the efforts, the accounts. Asked
    /// for when the list opens, off the input path, and may take as long as a network does; the screen shows what it has meanwhile.
    func choices(for command: String) async -> [ChoiceRow]

    /// Commits one value in the interactive configuration editor; updates report the saved rows or the refusal.
    func commitConfig(
        scope: String, path: [String], value: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async

    /// The answer to a question ``ConversationUpdate/askInput(id:prompt:secret:)`` put; nil when the person cancelled it.
    func answer(input id: Int, with text: String?)

    /// A runner's recent output, for the lane that shows it: bounded, the newest part, and never more than the runner wrote.
    func runnerOutput(_ id: String) async -> String

    /// Watches the focused runner until cancelled. Updates replace its bounded output snapshot, not the main transcript.
    func watchRunnerOutput(_ id: String, update: @escaping @Sendable (String) -> Void) -> Task<Void, Never>

    /// Watches a yielded process without consuming its model-facing unread output.
    func watchJob(_ id: String, update: @escaping @Sendable (JobUpdate) -> Void) -> Task<Void, Never>

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

    /// Never asks questions, so never answered.
    public func answer(questions id: Int, with answers: [QuestionAnswer]?) {}

    /// No commands of its own.
    public var commands: [SlashCommand] { [] }

    /// No files to offer.
    public func projectFiles() async -> ProjectFiles { ProjectFiles() }

    /// No lists.
    public func choices(for command: String) async -> [ChoiceRow] { [] }

    public func commitConfig(
        scope: String, path: [String], value: String, update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async {
        update(.notice("Configuration editing is unavailable.", isError: true))
    }

    /// Never asks for input, so never answered.
    public func answer(input id: Int, with text: String?) {}

    /// No skills to offer.
    public func skillCommands() async -> [SlashCommand] { [] }

    /// No runners, so no output.
    public func runnerOutput(_ id: String) async -> String { "" }

    /// A conversation without live runners supplies its one snapshot.
    public func watchRunnerOutput(_ id: String, update: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        Task { update(await runnerOutput(id)) }
    }

    /// A conversation without process jobs has no snapshots to send.
    public func watchJob(_ id: String, update: @escaping @Sendable (JobUpdate) -> Void) -> Task<Void, Never> {
        Task {}
    }

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
