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

    /// `start`, with the pictures the person pasted into `prompt` (roadmap 0224).
    func start(_ prompt: String, images: [ToolImage], update: @escaping @Sendable (ConversationUpdate) -> Void)
        -> Task<Void, Never>

    /// `enqueue`, with the pictures the person pasted into `text` (roadmap 0224).
    func enqueue(_ text: String, images: [ToolImage], id: Int, followUp: Bool)

    /// A picture the person pasted, as it will be sent (roadmap 0224): bounded as the read tool bounds one, or refused with the
    /// reason, such as a model that takes no images.
    func preparePicture(_ bytes: [UInt8]) async -> PicturePreparation

    /// Takes back queued message `id` before the run takes it (roadmap 0174).
    /// - Returns: false when the run has taken it, or it is not queued.
    func withdraw(_ id: Int) -> Bool

    /// The user's answer to the question ``ConversationUpdate/askApproval(id:question:)`` asked.
    func answer(approval id: Int, with choice: ApprovalChoice)
    /// The person's answers to the questions ``ConversationUpdate/askQuestions(id:questions:)`` asked, or nil when they declined.
    func answer(questions id: Int, with answers: [QuestionAnswer]?)

    /// The commands this conversation understands, beyond the screen's own `/help` and `/quit`.
    var commands: [SlashCommand] { get }

    /// The project's files, listed for the `@` picker: relative to the working directory, only what ask may read, bounded. Asked for when
    /// an `@` first appears and again once the listing is old, off the input path.
    func projectFiles() async -> ProjectFiles

    /// Whether a relative reply path may be linked: the current read policy, and no traversal through symlinks.
    func replyPathExists(_ path: String) -> Bool

    /// The skills the `/` picker offers, as commands named `skill:name` with their descriptions. Asked for once, when the picker first opens.
    func skillCommands() async -> [SlashCommand]

    /// What `/command ` offers to choose from, for a command that ``SlashCommand/takesChoices``: the models, the efforts, the accounts. Asked
    /// for when the list opens, off the input path, and may take as long as a network does; the screen shows what it has meanwhile.
    func choices(for command: String) async -> [ChoiceRow]

    /// Commits one value in the interactive configuration editor; updates report the saved rows or the refusal.
    func commitConfig(
        scope: String,
        path: [String],
        value: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async

    /// The answer to a question ``ConversationUpdate/askInput(id:prompt:secret:)`` put; nil when the person cancelled it.
    func answer(input id: Int, with text: String?)

    /// A runner's recent output, for the lane that shows it: bounded, the newest part, and never more than the runner wrote.
    func runnerOutput(_ id: String) async -> String

    /// What a click on `uri` opens with, from the person's openers (roadmap 0216).
    func opening(for uri: String) -> LinkOpening

    /// Runs the person's `!` command in their shell (note n56), its block arriving through `update`; with `sends`, its result is then
    /// sent to the model as their message (``ConversationUpdate/submitPrompt(_:)``), else it goes with their next one.
    func shell(_ command: String, sends: Bool, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<
        Void, Never
    >

    /// Runs the command the person's openers name for `uri`, asking first unless it was allowed (ADR-0148). What it asks and says
    /// arrives through `update`.
    func runOpener(for uri: String, update: @escaping @Sendable (ConversationUpdate) -> Void)

    /// What the person typed in thread `id`'s lane (roadmap 0194): steering while it runs, its next message once it has ended.
    func sendToThread(_ id: String, text: String, update: @escaping @Sendable (ConversationUpdate) -> Void)

    /// Ctrl+C in thread `id`'s lane while it works: it stops, with the threads under it (roadmap 0195).
    func stopThread(_ id: String, update: @escaping @Sendable (ConversationUpdate) -> Void)

    /// `/rename TITLE` in thread `id`'s lane (roadmap 0195).
    func renameThread(_ id: String, to title: String, update: @escaping @Sendable (ConversationUpdate) -> Void)

    /// `/merge` in thread `id`'s lane: merge it now, with the unmerged threads under it (roadmap 0195).
    func mergeThread(_ id: String, update: @escaping @Sendable (ConversationUpdate) -> Void)

    /// The screen now shows lane `id`, a runner's, or main when nil.
    func laneShown(_ id: String?)

    /// `/thread TEXT` typed in thread `parent`'s lane: a thread forked from that thread's conversation, listed under it.
    func startThread(_ text: String, from parent: String, update: @escaping @Sendable (ConversationUpdate) -> Void)
        async

    /// Watches the focused runner until cancelled. Updates replace its bounded output snapshot, not the main transcript.
    func watchRunnerOutput(_ id: String, update: @escaping @Sendable (String) -> Void) -> Task<Void, Never>

    /// Watches a yielded process without consuming its model-facing unread output.
    func watchJob(_ id: String, update: @escaping @Sendable (JobUpdate) -> Void) -> Task<Void, Never>

    /// Sends the command the current run waits on to the background (roadmap 0173); false when it waits on none.
    func sendCommandToBackground() -> Bool
    /// Starts anything that reports on its own while the screen is open, such as a new build appearing, until the
    /// returned task is cancelled. Nil when there is nothing to watch.
    func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>?

    /// Runs the command `name`, one of ``commands``. It is a run like a prompt's: updates arrive through
    /// `update`, ending with ``ConversationUpdate/runEnded``, and cancelling the task aborts it.
    func command(
        _ name: String,
        arguments: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never>

    /// Runs the command `name` beside a running turn (roadmap 0113): its updates arrive through `update`, without
    /// ``ConversationUpdate/runEnded``, since the screen's run is the turn's: its end is ``ConversationUpdate/besideEnded``.
    func command(
        _ name: String,
        arguments: String,
        beside: Bool,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never>
}
