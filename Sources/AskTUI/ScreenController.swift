internal import TerminalKitCodecs
public import TerminalKitInput
internal import TerminalKitText

/// The screen's behaviour as a pure state machine: events in, state and effects out. The driver performs the
/// effects; tests drive this directly.
public struct ScreenController: Sendable {
    /// Something the driver must do.
    public enum Effect: Sendable, Equatable {
        case startRun(String)
        case queuePrompt(id: Int, text: String, followUp: Bool)
        /// Take a queued message back, to edit it (roadmap 0174); ``ConversationUpdate/promptWithdrawn(id:withdrawn:)`` answers.
        case withdrawPrompt(id: Int)
        case runCommand(name: String, arguments: String)
        /// Run a command beside the running turn, which goes on (roadmap 0113): it is not the screen's run.
        case runCommandBeside(name: String, arguments: String)
        /// Run the person's `!` command now, beside any turn (note n56); with `sends`, its result goes to the model after.
        case runShell(String, sends: Bool)
        /// Tell the person, who looks elsewhere, with this text (`ui.notify`, note n62).
        case notify(String)
        case cancelRun
        /// Put this text on the clipboard.
        case copy(String)
        /// Open a link the person clicked (roadmap 0075), as ``LinkOpener`` allows.
        case openLink(String)
        /// Read the host's pasteboard and paste it, as a bracketed paste would (roadmap 0082).
        case pasteFromClipboard
        case answerApproval(id: Int, ApprovalChoice)
        /// The answers to the model's questions, or nil when the person declined (roadmap 0117).
        case answerQuestions(id: Int, [QuestionAnswer]?)
        /// List the project's files for the `@` picker; the answer is ``ConversationUpdate/files(_:)``.
        case indexFiles
        /// Read a runner's recent output for its lane; the answer is ``ConversationUpdate/runnerOutput(id:text:)``.
        case readRunnerOutput(id: String)
        /// What the person typed in a thread's lane (roadmap 0194), for that thread.
        case sendToThread(id: String, text: String)
        /// Ctrl+C in a thread's lane while it works (roadmap 0195).
        case stopThread(id: String)
        /// `/rename TITLE` in a thread's lane.
        case renameThread(id: String, title: String)
        /// `/merge` (or `/close`) in a thread's lane: merge it now, with the threads under it.
        case mergeThread(id: String)
        /// `threads.questions` `after`: wake the screen when a thread's question has waited `after`.
        case armThreadQuestionTimer(after: Duration)
        /// `/thread TEXT` typed in thread `from`'s lane: a thread forked from that one.
        case startThread(from: String, text: String)
        /// Follow a yielded process in its original tool block until it ends.
        case watchJob(id: String)
        /// Tell the screen when the quit window closes: Ctrl+C was pressed on an empty, idle input and a second press within this long quits.
        case armQuitTimer(generation: Int)
        /// Tell the screen when the sandbox note, shown by a click on the status mark, has been up long enough (roadmap 0133).
        case armSandboxNoteTimer(generation: Int)
        /// List the skills for the `/` picker; the answer is ``ConversationUpdate/skills(_:)``.
        case listSkills
        /// List what `command` offers to choose from; the answer is ``ConversationUpdate/choices(command:rows:)``.
        case listChoices(command: String)
        /// Commit one configuration value through the composition root.
        case commitConfig(scope: String, path: [String], value: String)
        /// The person answered what a command asked for, or cancelled it (nil).
        case answerInput(id: Int, text: String?)
        /// Send the command the model waits on to the background (roadmap 0173).
        case sendCommandToBackground
        case quit
    }

    public internal(set) var state: ScreenState
    /// The commands the screen answers itself (`/help`, `/quit`) and those the conversation runs.
    let commands: [SlashCommand]
    var pending: [Pending] = []
    var turnCommands = TurnCommands()
    /// The screen's height as of the last key, which sizes the picker when a file listing arrives between keys.
    var pickerScreenRows = 0
    /// The commands whose lists were asked for and have not arrived, so a key does not ask twice.
    var asking: Set<String> = []
    var nextPromptID = 0
    /// The queued message being taken back, until the agent answers (roadmap 0174).
    var withdrawing: Int?
    /// The number of the quit window last opened, so a timer for an earlier one cannot close a later one.
    var quitGeneration = 0
    var acceptsInput = false
    var returningInput = false
    /// Whether the person stopped the turn (Esc or Ctrl+C), not a failure: only then do the queued messages follow `ui.interruptSendsQueued`.
    var interruptedByPerson = false
    /// What was sent, for Up and Down (roadmap 0111).
    var history = PromptHistory()
    let options: ScreenOptions
    /// What the last frame drew, set by the driver before it hands over a mouse event.
    var frame = FrameGeometry()
    var pointer = PointerRecognizer<Int>()
    var selector = SelectionController<Int>()
    var autoscroll = DragAutoscroll()
    var inputDrag = InputDrag()
    /// Where a selection made with the keyboard began, while one is being made.
    var inputAnchor: Int?
    /// The number of the latest copy, for dropping a late result of an earlier one.
    var copyGeneration = 0

    /// What `/help` and `/quit` are, always present.
    // @dl:accept -- a table of command names and summaries beside the conversation's own table; the entries are the data
    static let builtIn = [
        SlashCommand(
            // @dl:accept -- the built-in commands read like the conversation's: a name and a sentence each, as data
            name: "help",
            summary:
                // @dl:accept -- the built-in commands read like the conversation's: a name and a sentence each, as data
                "List commands. Ctrl+C: erase, stop, quit (twice). Ctrl+T/O/G fold. Enter steers."
                // @dl:accept -- adjacent command-table entries match the conversation's table by shape, not by command or behavior
        ),
        // @dl:accept -- a quit entry belongs to both command tables; each screen owns its own sentence
        // @dl:accept -- the built-in list reads alike entry to entry because every entry is a name and a sentence
        // @dl:accept -- a built-in entry and a conversation entry share a table's shape; the sentences are the data
        SlashCommand(name: "quit", summary: "Leave ask, stopping a running turn first."),
        // @dl:accept -- a follow-up entry and a tree entry share a command table's shape; the sentences are the data
        SlashCommand(
            name: "continue",
            // @dl:accept -- a continue entry and a conversation entry share a command table's shape; the sentences are the data
            summary: "Tell the agent to carry on where it stopped. Also: continue, resume, go ahead, go."
        ),
        // @dl:accept -- a follow-up entry and a tree entry share a command table's shape; the sentences are the data
        SlashCommand(name: "follow-up", summary: "Queue a message after the agent finishes: /follow-up TEXT."),
        SlashCommand(name: "jobs", summary: "Show or hide the background jobs that are running."),
        SlashCommand(
            name: "sidebar",
            summary: "Show or hide the runner sidebar (Ctrl+\\). Wide screens only.",
            category: .tools
        ),
        SlashCommand(
            name: "verbose",
            summary: "Show or hide details: the sandbox, the files read, builds that appeared.",
            category: .tools
        )
    ]

    /// A controller showing `label` in the status line, answering `commands` besides the built-in ones.
    public init(label: String, commands: [SlashCommand] = [], options: ScreenOptions = ScreenOptions()) {
        state = ScreenState(label: label, options: options)
        self.commands = Self.builtIn + commands
        self.options = options
        state.blocks.commands = Self.linkedNames(self.commands, skills: [])
        state.transcript.setToolsFoldedByDefault(options.foldTools)
        state.transcript.setThinkingFoldedByDefault(options.foldThinking)
        state.transcript.setCodeFoldedByDefault(options.foldCode)
        state.transcript.setCodeFoldLines(options.codeFoldLines)
        state.transcript.setOutputFoldLimits(lines: options.outputFoldLines, bytes: options.outputFoldBytes)
        state.transcript.setMarkdown(options.markdown)
        state.transcript.setHighlight(options.highlight)
        state.transcript.shimmer = options.shimmer
        state.transcript.spinnerStyle = options.spinner
        state.transcript.localizedDurations = options.localizedDurations
        state.transcript.timeoutDisplay = options.timeoutDisplay
        state.transcript.timeoutLabel = options.timeoutLabel
        state.transcript.home = options.home
        state.promptRows = options.promptRows
        state.sidebarOpen = options.sidebar
        state.sidebarLayout = options.sidebarLayout
        state.jobsInTree = options.sidebarJobsInTree
        state.verbose = options.verbose
    }

    /// Applies terminal input. `pageRows` is how far Page Up and Page Down scroll.
    public mutating func handle(
        _ event: InputEvent,
        pageRows: Int,
        at now: ContinuousClock.Instant = .now,
        columns: Int? = nil
    ) -> [Effect] {
        disarmTurnAbort(unlessInterrupt: event)
        var effects = route(event, pageRows: pageRows, at: now, columns: columns)
        switch event {
            case .key, .paste:
                pickerScreenRows = pageRows + 3
                effects += refreshPicker(screenRows: pickerScreenRows, at: now)
            default: break
        }
        return effects
    }

    /// The keys that belong to a selection or to a fold, before the editor: Shift with a cursor key, what a selection in the input or the
    /// transcript takes, and the three toggles. Nil when the key is none of them.
    mutating func selectionOrToggleKey(_ key: KeyEvent, columns: Int?) -> [Effect]? {
        if Self.isSelectingMove(key) {
            extendInputSelection(key, columns: columns)
            return []
        }
        if let effects = inputSelectionKey(key) { return effects }
        if let effects = selectionKey(key) { return effects }
        if let effects = clipboardChordKey(key) { return effects }
        if isToggleToolOutput(key) { return toggleAllToolOutput() }
        if isToggleThinking(key) { return toggleAllThinking() }
        if isToggleCode(key) { return toggleAllCode() }
        if isToggleSidebar(key) { return toggleSidebar() }
        return nil
    }

    /// Applies an update from the running conversation. A reader who has scrolled back stays on what they were reading (ADR-0072).
    @discardableResult
    public mutating func handle(_ update: ConversationUpdate) -> [Effect] {
        deliver(update)
    }

    mutating func edit(_ key: KeyEvent, columns: Int?, interrupt: Interrupt) -> [Effect] {
        if key.keyCode == Key.up.rawValue, key.modifiers == .alt, let effects = takeBackQueued() { return effects }
        // The rows as drawn: inside the box, or beside the sidebar's band, the draft is narrower than the screen (note n36).
        let columns = frame.prompt?.columns ?? columns
        let indent = columns.map { PromptLayout.prefix(state.promptPrefix, columns: $0).count } ?? 0
        switch state.editor.apply(key, columns: columns, firstRowIndent: indent) {
            case .submitted(let line):
                return submit(line, followUp: key.modifiers.contains(.alt))
            case .escape:
                return escapePressed(at: interrupt.at)
            case .interrupt:
                return interrupted(interrupt)
            case .endOfInput:
                return state.running ? [] : [.quit]
            case .ignored where key.modifiers.isEmpty && [Key.up.rawValue, Key.down.rawValue].contains(key.keyCode):
                // Up from the input's first row: the sent line before; Down from its last: the one after (roadmap 0111).
                let text = state.editor.text
                let line = key.keyCode == Key.up.rawValue ? history.older(than: text) : history.newer(than: text)
                if let line { state.editor.restore(line) }
                return []
            case .edited, .ignored:
                return []
        }
    }
}
