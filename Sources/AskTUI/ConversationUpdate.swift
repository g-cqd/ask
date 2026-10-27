internal import TerminalKitCodecs
internal import TerminalKitInput

/// What a running conversation tells the screen. The composition root maps agent events onto these.
public enum ConversationUpdate: Sendable, Equatable {
    /// A prompt the user wrote earlier, shown when a recorded session is resumed.
    case userPrompt(String)
    case assistantText(String)
    case toolStarted(name: String, summary: String, id: String? = nil, fullInput: String = "")
    /// More of the model's reasoning, shown as a block that starts folded.
    case thinkingText(String)
    /// The tool ended; `output` is what it returned, kept so the block can be opened.
    case toolFinished(Transcript.ToolStatus, output: String = "", id: String? = nil, backgroundJob: String? = nil)
    /// A background process updates its original tool block independently of focused output.
    case jobOutput(JobUpdate)
    case notice(String, isError: Bool)
    /// Something ask did on its own account that is not needed to read the conversation: shown with `--verbose` or after `/verbose`, kept for
    /// `/verbose` otherwise (ADR-0119).
    case detail(String)
    /// The left of the status line, such as the model, when it changes.
    case label(String)
    /// The label at several lengths, longest first, so a narrow terminal gets a whole shorter label and not half of the long one.
    case labelVariants([String])
    /// A short status for the status line, such as token usage.
    case status(String)
    /// Latest measured context occupancy and model capacity, separate from cumulative token spend.
    case context(String)
    /// Close the screen once the run that sent this has ended, so the caller can act on `exit`.
    case requestExit(ScreenExit)
    /// A queued message was persisted; remove its pending copy and show it in the conversation.
    case promptAccepted(id: Int, text: String)
    /// The run failed: return any unacknowledged messages to the editor when it ends.
    case returnQueuedPrompts
    /// Put a prompt back in the editor for rewriting, as after `/tree N`. An editor that already holds a draft keeps it, and the
    /// prompt is shown in a notice instead (ADR-0093).
    case fillDraft(String)
    /// Replaces the active conversation: clear its transcript, usage display and scrollback, keeping the draft.
    case clearConversation
    /// A tool call asks for more than the sandbox allows: ask the user, and send the answer to ``Conversation/answer(approval:with:)``.
    case askApproval(id: Int, question: String)
    /// Everything running beside the conversation, replacing the last list. The status line counts them and `/tasks` lists them.
    case runners([RunnerInfo])
    /// The project's files for the `@` picker, answering ``ScreenController/Effect/indexFiles``.
    case files(ProjectFiles)
    /// The skills for the `/` picker, as commands named `skill:name`, answering ``ScreenController/Effect/listSkills``.
    case skills([SlashCommand])
    /// A command's list, answering ``ScreenController/Effect/listChoices(command:)``.
    case choices(command: String, rows: [ChoiceRow])
    /// The running command wants a line from the person: shown as a question in the status line, answered with Enter, cancelled with Esc, and sent to
    /// ``Conversation/answer(input:with:)``. A secret is hidden as it is typed and never reaches the transcript.
    case askInput(id: Int, prompt: String, secret: Bool)
    /// A runner's recent output, answering ``ScreenController/Effect/readRunnerOutput(id:)``.
    case runnerOutput(id: String, text: String)
    /// Whether the sandbox is active for this session.
    case sandboxActive(Bool)
    /// The run is over, however it ended.
    case runEnded
}
