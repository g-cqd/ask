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
        case cancelRun
        /// Put this text on the clipboard.
        case copy(String)
        case answerApproval(id: Int, ApprovalChoice)
        /// List the project's files for the `@` picker; the answer is ``ConversationUpdate/files(_:)``.
        case indexFiles
        /// Read a runner's recent output for its lane; the answer is ``ConversationUpdate/runnerOutput(id:text:)``.
        case readRunnerOutput(id: String)
        /// Tell the screen when the quit window closes: Ctrl+C was pressed on an empty, idle input and a second press within this long quits.
        case armQuitTimer(generation: Int)
        /// List the skills for the `/` picker; the answer is ``ConversationUpdate/skills(_:)``.
        case listSkills
        /// List what `command` offers to choose from; the answer is ``ConversationUpdate/choices(command:rows:)``.
        case listChoices(command: String)
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
        ),
        SlashCommand(name: "quit", summary: "Leave ask, stopping a running turn first."),
        SlashCommand(name: "follow-up", summary: "Queue a message after the agent finishes: /follow-up TEXT."),
        SlashCommand(name: "tasks", summary: "Show or hide the background jobs that are running."),
        SlashCommand(name: "sidebar", summary: "Show or hide the runner sidebar (Ctrl+\\). Wide screens only."),
        SlashCommand(
            name: "verbose", summary: "Show or hide details: the sandbox, the files read, builds that appeared.")
    ]

    /// A controller showing `label` in the status line, answering `commands` besides the built-in ones.
    public init(label: String, commands: [SlashCommand] = [], options: ScreenOptions = ScreenOptions()) {
        state = ScreenState(label: label)
        self.commands = Self.builtIn + commands
        self.options = options
        state.transcript.setToolsFoldedByDefault(options.foldTools)
        state.transcript.setThinkingFoldedByDefault(options.foldThinking)
        state.transcript.setCodeFoldedByDefault(options.foldCode)
        state.transcript.setCodeFoldLines(options.codeFoldLines)
        state.promptRows = options.promptRows
        state.sidebarOpen = options.sidebar
        state.verbose = options.verbose
    }

    /// Applies terminal input. `pageRows` is how far Page Up and Page Down scroll.
    public mutating func handle(
        _ event: InputEvent, pageRows: Int, at now: ContinuousClock.Instant = .now, columns: Int? = nil
    ) -> [Effect] {
        var effects = route(event, pageRows: pageRows, at: now, columns: columns)
        switch event {
            case .key, .paste:
                pickerScreenRows = pageRows + 3
                effects += refreshPicker(screenRows: pickerScreenRows, at: now)
            default: break
        }
        return effects
    }

    private mutating func route(
        _ event: InputEvent, pageRows: Int, at now: ContinuousClock.Instant, columns: Int?
    ) -> [Effect] {
        switch event {
            case .key(let key):
                // Any key but the second Ctrl+C ends the quit window (roadmap 0064): what was armed is read here, then cleared.
                let armedAt = state.quitArmedAt
                state.quitArmedAt = nil
                if key.keyCode == Key.pageUp.rawValue {
                    state.scrollback += Swift.max(1, pageRows)
                    return []
                }
                if key.keyCode == Key.pageDown.rawValue {
                    state.scrollback = Swift.max(0, state.scrollback - Swift.max(1, pageRows))
                    return []
                }
                // End goes to the end of the conversation when there is no draft for it to go to the end of (ADR-0072).
                if key.keyCode == Key.end.rawValue, state.scrollback > 0, state.editor.text.isEmpty {
                    state.scrollback = 0
                    return []
                }
                // A question waiting for y, a or n takes the keys first (roadmap 0019).
                if state.pendingApproval != nil { return answer(key) }
                // A line a command asked for, such as a pasted code or a key, takes every key but the scrolling ones above.
                if state.pendingInput != nil { return answerInput(key) }
                if let effects = selectionOrToggleKey(key, columns: columns) { return effects }
                if let effects = pickerKey(key, screenRows: pageRows + 3) { return effects }
                if let effects = stripKey(key) { return effects }
                clearSelection()
                return edit(key, columns: columns, interrupt: Interrupt(at: now, armedAt: armedAt))
            case .mouse(let mouse):
                return handle(mouse: mouse, at: now)
            case .paste(let text) where state.pendingInput != nil:
                state.inputAnswer.paste(text.filter { !$0.isNewline })
                return []
            case .paste(let text):
                removeInputSelection()
                clearSelection()
                state.editor.paste(text)
                return []
            default:
                return []
        }
    }

    /// The keys that belong to a selection or to a fold, before the editor: Shift with a cursor key, what a selection in the input or the
    /// transcript takes, and the three toggles. Nil when the key is none of them.
    private mutating func selectionOrToggleKey(_ key: KeyEvent, columns: Int?) -> [Effect]? {
        if Self.isSelectingMove(key) {
            extendInputSelection(key, columns: columns)
            return []
        }
        if let effects = inputSelectionKey(key) { return effects }
        if let effects = selectionKey(key) { return effects }
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
        switch update {
            case .userPrompt(let text): state.transcript.addUser(text)
            case .assistantText(let text): state.transcript.addAssistantText(text)
            case .thinkingText(let text): state.transcript.addThinkingText(text)
            case .toolStarted(let name, let summary): state.transcript.startTool(name: name, summary: summary)
            case .toolFinished(let status, let output): state.transcript.finishTool(status, output: output)
            case .notice(let text, let isError): state.transcript.addNotice(text, isError: isError)
            case .detail(let text): receive(detail: text)
            case .requestExit(let exit): state.exitRequest = exit
            case .label(let text):
                state.label = text
                state.labelVariants = []
            case .labelVariants(let forms):
                guard let first = forms.first else { break }
                state.label = first
                state.labelVariants = forms
            case .status(let text): state.detail = text
            case .runners(let list): setRunners(list)
            case .runnerOutput: break
            case .files(let list): return receive(files: list)
            case .skills(let list): receive(skills: list)
            case .choices(let command, let rows): return receive(command: command, choices: rows)
            case .askInput(let id, let prompt, let secret): askInput(id: id, prompt: prompt, secret: secret)
            case .fillDraft(let text):
                fill(draft: text)
                // A draft that is a command with a list opens it, without waiting for a key.
                return refreshPicker(screenRows: pickerScreenRows, at: .now)
            case .promptAccepted(let id, let text):
                pending.removeAll { $0.id == id }
                state.transcript.addUser(text)
            case .returnQueuedPrompts: returningInput = true
            case .clearConversation:
                state.transcript.removeAll()
                clearSelection()
                state.detail = ""
                state.scrollback = 0
            case .askApproval(let id, let question): ask(id: id, question: question)
            case .runEnded:
                state.pendingApproval = nil
                state.pendingInput = nil
                state.inputAnswer.clear()
                return endRun()
        }
        return []
    }

    mutating func edit(_ key: KeyEvent, columns: Int?, interrupt: Interrupt) -> [Effect] {
        let indent = columns.map { PromptLayout.prefix(columns: $0).count } ?? 0
        switch state.editor.apply(key, columns: columns, firstRowIndent: indent) {
            case .submitted(let line):
                return submit(line, followUp: key.modifiers.contains(.alt))
            case .escape:
                return escapePressed()
            case .interrupt:
                return interrupted(interrupt)
            case .endOfInput:
                return state.running ? [] : [.quit]
            case .edited, .ignored:
                return []
        }
    }
}
