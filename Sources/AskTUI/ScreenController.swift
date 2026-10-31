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
        case runCommand(name: String, arguments: String)
        /// Run a command beside the running turn, which goes on (roadmap 0113): it is not the screen's run.
        case runCommandBeside(name: String, arguments: String)
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
        case quit
    }

    public internal(set) var state: ScreenState
    /// The commands the screen answers itself (`/help`, `/quit`) and those the conversation runs.
    let commands: [SlashCommand]
    var pending: [Pending] = []
    /// The screen's height as of the last key, which sizes the picker when a file listing arrives between keys.
    var pickerScreenRows = 0
    /// The commands whose lists were asked for and have not arrived, so a key does not ask twice.
    var asking: Set<String> = []
    var nextPromptID = 0
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
            summary: "Tell the agent to carry on where it stopped. Also: continue, resume, go ahead, go."),
        // @dl:accept -- a follow-up entry and a tree entry share a command table's shape; the sentences are the data
        SlashCommand(name: "follow-up", summary: "Queue a message after the agent finishes: /follow-up TEXT."),
        SlashCommand(name: "jobs", summary: "Show or hide the background jobs that are running. Also /tasks."),
        SlashCommand(
            name: "sidebar", summary: "Show or hide the runner sidebar (Ctrl+\\). Wide screens only.", category: .tools),
        SlashCommand(
            name: "verbose", summary: "Show or hide details: the sandbox, the files read, builds that appeared.",
            category: .tools)
    ]

    /// A controller showing `label` in the status line, answering `commands` besides the built-in ones.
    public init(label: String, commands: [SlashCommand] = [], options: ScreenOptions = ScreenOptions()) {
        state = ScreenState(label: label, options: options)
        self.commands = Self.builtIn + commands
        self.options = options
        state.transcript.setToolsFoldedByDefault(options.foldTools)
        state.transcript.setThinkingFoldedByDefault(options.foldThinking)
        state.transcript.setCodeFoldedByDefault(options.foldCode)
        state.transcript.setCodeFoldLines(options.codeFoldLines)
        state.transcript.setMarkdown(options.markdown)
        state.transcript.spinnerStyle = options.spinner
        state.transcript.localizedDurations = options.localizedDurations
        state.transcript.timeoutDisplay = options.timeoutDisplay
        state.transcript.timeoutLabel = options.timeoutLabel
        state.transcript.home = options.home
        state.promptRows = options.promptRows
        state.sidebarOpen = options.sidebar
        state.verbose = options.verbose
    }

    /// Applies terminal input. `pageRows` is how far Page Up and Page Down scroll.
    public mutating func handle(
        _ event: InputEvent, pageRows: Int, at now: ContinuousClock.Instant = .now, columns: Int? = nil
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

    mutating func apply(_ update: ConversationUpdate) -> [Effect] {
        if update.showsTheModelIsBack { modelIsBack() }
        switch update {
            case .batch(let updates): return updates.flatMap { apply($0) }
            case .userPrompt(let text): replayPrompt(text)
            case .assistantText(let text): state.transcript.addAssistantText(text)
            case .thinkingText(let text): state.transcript.addThinkingText(text)
            case .toolStarted(let name, let summary, let id, let input, let command):
                state.transcript.startTool(name: name, summary: summary, id: id, fullInput: input, command: command)
            case .toolFinished(let status, let output, let id, let job):
                state.transcript.finishTool(status, output: output, id: id, backgroundJob: job)
                if let job { return [.watchJob(id: job)] }
            case .jobOutput(let job): state.transcript.updateJob(job)
            case .notice(let text, let isError):
                state.transcript.addNotice(HomePath.abbreviate(text, home: options.home), isError: isError)
            case .detail(let text): receive(detail: HomePath.abbreviate(text, home: options.home))
            case .requestExit(let exit): state.exitRequest = exit
            case .label(let text):
                state.label = text
                state.labelVariants = []
            case .labelVariants(let forms):
                guard let first = forms.first else { break }
                state.label = first
                state.labelVariants = forms
            case .sandboxActive(let active): state.sandboxed = active
            case .sessionIdentity(let seed): state.sessionIdentity = seed
            case .status(let text): state.detail = text
            case .context(let text): state.context = text
            case .runners(let list): setRunners(list)
            case .runnerOutput: break
            case .files(let list): return receive(files: list)
            case .skills(let list): receive(skills: list)
            case .choices(let command, let rows): return receive(command: command, choices: rows)
            case .configEditor(let snapshot): return receive(config: snapshot)
            case .askInput(let id, let prompt, let secret): askInput(id: id, prompt: prompt, secret: secret)
            case .fillDraft(let text):
                fill(draft: text)
                // A draft that is a command with a list opens it, without waiting for a key.
                return refreshPicker(screenRows: pickerScreenRows, at: .now)
            case .promptAccepted(let id, let text):
                replaceQueuedPrompt(id: id, text: text)
            case .returnQueuedPrompts: returningInput = true
            case .clearConversation:
                state.transcript.removeAll()
                clearSelection()
                state.detail = ""
                state.context = ""
                state.scrollback = 0
            case .askApproval(let id, let question, let kind, let detail):
                ask(id: id, question: question, kind: kind, detail: detail)
            case .askQuestions(let id, let questions): askQuestions(id: id, questions: questions)
            case .compacting, .compactionFinished, .reconnecting, .connectingMCP, .waitingForNetwork:
                applyBackgroundWork(update)
            case .runEnded: return runEnded()
        }
        return []
    }

    mutating func edit(_ key: KeyEvent, columns: Int?, interrupt: Interrupt) -> [Effect] {
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
