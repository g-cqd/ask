internal import TerminalKitCodecs
internal import TerminalKitInput

/// What a running conversation tells the screen. The composition root maps agent events onto these.
public enum ConversationUpdate: Sendable, Equatable {
    /// A prompt the user wrote earlier, shown when a recorded session is resumed.
    case userPrompt(String)
    /// Several updates applied as one, in order, and drawn once: a conversation rebuilt at once (`/rewind`, roadmap 0160) would
    /// otherwise draw a frame, and copy the transcript, for every item.
    indirect case batch([ConversationUpdate])
    /// What names this session, for a colour of its own on the status line (roadmap 0164); nil takes the colour away.
    case sessionIdentity(String?)
    case assistantText(String)
    /// A tool began. With `command`, the full input is a command, which heads the block after its limits, and `summary` is unused.
    /// `path` is the file the call names, whose language colours a file's text in the block (roadmap 0152).
    case toolStarted(
        name: String,
        summary: String,
        id: String? = nil,
        fullInput: String = "",
        command: ToolCommand? = nil,
        path: String? = nil
    )
    /// More of the model's reasoning, shown as a block that starts folded.
    case thinkingText(String)
    /// The tool ended; `output` is what it returned, kept so the block can be opened. `replacements` is the count an edit
    /// reported, shown after its target.
    case toolFinished(
        Transcript.ToolStatus,
        output: String = "",
        id: String? = nil,
        backgroundJob: String? = nil,
        replacements: Int? = nil
    )
    /// A background process updates its original tool block independently of focused output.
    case jobOutput(JobUpdate)
    /// How far the running tool started as `id` has got, as one short line shown on its header until it ends (roadmap 0067).
    case toolProgress(id: String, text: String)
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
    /// Like `fillDraft`, with the draft's list closed: a draft to edit, whose own words would match a row of it (roadmap 0180).
    case editDraft(String)
    /// Replaces the active conversation: clear its transcript, usage display and scrollback, keeping the draft.
    case clearConversation
    /// A tool call asks for more than the sandbox allows: ask the user, and send the answer to ``Conversation/answer(approval:with:)``.
    case askApproval(id: Int, question: String, kind: ApprovalKind = .grant, detail: String? = nil)
    /// The model's questions for the person (roadmap 0117); answered with ``Conversation/answer(questions:with:)``.
    case askQuestions(id: Int, questions: [ScreenQuestion])
    /// Everything running beside the conversation, replacing the last list. The status line counts them and `/jobs` lists them.
    case runners([RunnerInfo])
    /// When runners last did something, by id: a job's last output (roadmap 0195, note n15). Merged into what is known.
    case runnerActivity([String: ContinuousClock.Instant])
    /// The project's files for the `@` picker, answering ``ScreenController/Effect/indexFiles``.
    case files(ProjectFiles)
    /// The skills for the `/` picker, as commands named `skill:name`, answering ``ScreenController/Effect/listSkills``.
    case skills([SlashCommand])
    /// A command's list, answering ``ScreenController/Effect/listChoices(command:)``.
    case choices(command: String, rows: [ChoiceRow])
    /// A command's list changed where it comes from (an MCP server's resources, as `@server`): asked for again when next shown.
    case choicesStale(command: String)
    /// Replaces the interactive configuration editor's rows.
    case configEditor(ConfigEditorSnapshot)
    /// The running command wants a line from the person: shown as a question in the status line, answered with Enter, cancelled with Esc, and sent to
    /// ``Conversation/answer(input:with:)``. A secret is hidden as it is typed and never reaches the transcript.
    /// `transient`: the prompt leaves the transcript once answered or cancelled, for what is to be seen once (a recovery code).
    case askInput(id: Int, prompt: String, secret: Bool, transient: Bool = false)
    /// The conversation did not take a queued message (a skill that cannot be loaded): it goes back to the input.
    case promptRefused(id: Int)
    /// Whether queued message `id` was taken back before the run took it (roadmap 0174).
    case promptWithdrawn(id: Int, withdrawn: Bool)
    /// A command run beside the screen's run ended (roadmap 0113).
    case besideEnded
    /// A runner's recent output, answering ``ScreenController/Effect/readRunnerOutput(id:)``.
    case runnerOutput(id: String, text: String)
    /// Whether the sandbox is active for this session.
    case sandboxActive(Bool)
    /// The connection dropped and ask is waiting to try again: the status bar says `Reconnecting...` until the model answers again.
    case reconnecting(Bool)
    /// The turn waits for the MCP servers it connects on first need (roadmap 0143): the status bar says `Connecting MCP...` until false.
    case connectingMCP(Bool)
    /// A request failed with the network gone, and ask waits for it to come back (roadmap 0141): the status bar says so until the next
    /// attempt, the model's answer or the run's end.
    case waitingForNetwork
    /// A compaction began (true) or ended (false): the status bar says `Compacting...` meanwhile (roadmap 0099).
    case compacting(Bool)
    /// A compaction ended, with its summary or the reason it failed (roadmap 0105). It finishes the block `compacting(true)` started; with
    /// none running, as when a session is shown again, it is a block already done.
    /// `tokens`, when known, says what the compaction did in the block's header: `182k → 3.1k tokens` (roadmap 0176).
    case compactionFinished(Transcript.ToolStatus, text: String, tokens: String? = nil)
    /// A `/btw` aside began (roadmap 0194): a block of its own colour, headed by the question, that the run's end does not touch.
    case asideStarted(id: String, question: String, name: String = "btw")
    /// The aside's answer, or why there is none.
    case asideFinished(id: String, Transcript.ToolStatus, answer: String)
    /// Where a thread started (roadmap 0195, note n23): a block of its own at the fork point of the conversation it was forked from.
    case threadStarted(id: String, name: String, prompt: String)
    /// A thread merged into this conversation: a folded block that opens onto its summary, which goes to the model with what is
    /// sent next.
    case threadMerged(id: String, name: String, prompt: String, summary: String)
    /// Show thread `id`'s lane, as a reload found it (roadmap 0195).
    case focusThread(id: String)
    /// What happened in a thread (roadmap 0194): drawn in that thread's conversation, never main's.
    indirect case thread(id: String, ConversationUpdate)
    /// The run is over, however it ended.
    case runEnded
}
