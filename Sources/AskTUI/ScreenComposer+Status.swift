internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The status line, fitted to `columns`, and where its clickable parts sit. Each piece is whole, shorter or gone, never cut (roadmap 0074).
    /// It says nothing that conveys nothing: no "ready", and a copy only when it went wrong.
    static func status(
        for state: ScreenState,
        input: String = "",
        columns: Int = 200,
        trailingRunners: Bool = false
    ) -> (line: Line, runners: Range<Int>?, below: Range<Int>?) {
        let mark = leadingMark(for: state)
        var style = StatusLine.statusStyle
        // The session's colour, when it has one (roadmap 0164) and `ui.sessionTint` puts it here, behind the whole line.
        if let seed = state.sessionIdentity, state.sessionTint.status {
            style.bg = state.blocks.theme.sessionTint(seed: seed)
        }
        var line = StatusLine(
            segments(for: state, input: input, mark: mark),
            columns: columns,
            markStyle: mark.style,
            markWidth: UnicodeWidth.displayWidth(of: mark.character)
        )
        line.trailingRunners = trailingRunners
        var drawn = line.line(style: style)
        // The mark keeps its colour on the session's background, not a hole in it.
        for index in drawn.line.accents.indices where drawn.line.accents[index].style.bg == .default {
            drawn.line.accents[index].style.bg = style.bg
        }
        return drawn
    }

    /// Whether what is shown works: main's turn, or in a thread's lane that thread (note n35), whatever main does.
    static func focusedWorks(_ state: ScreenState) -> Bool {
        guard let lane = state.lane, lane.isThread else { return state.running }
        return state.runners.first { $0.id == lane.id }?.state.isActive ?? false
    }

    /// The columns of the idle mark, which a click names (roadmap 0133); nil while anything else leads the line.
    static func markColumns(for state: ScreenState) -> Range<Int>? {
        guard !(focusedWorks(state) || state.compacting || state.reconnecting) else { return nil }
        return 0 ..< UnicodeWidth.displayWidth(of: leadingMark(for: state).character)
    }

    /// Evaluates a stable per-operation spinner while running, or the sandbox-colored idle `!`.
    static func leadingMark(for state: ScreenState) -> StatusLeadingMark {
        guard focusedWorks(state) || state.compacting || state.reconnecting else {
            return StatusLeadingMark.idle(sandboxed: state.sandboxed, named: state.sandboxNoteShown)
        }
        let configured = state.transcript.spinnerStyle
        let clock = state.transcript.progress[state.transcript.items.count - 1].flatMap { $0.ended == nil ? $0 : nil }
        let spinner = configured == .random ? (clock?.spinner ?? state.statusSpinner) : configured
        let frames = spinner.frames
        let index = configured == .random ? (clock?.frame ?? state.statusFrame) : state.statusFrame
        let frame = frames.isEmpty ? "|" : frames[index % frames.count]
        if state.compacting { return StatusLeadingMark.compactingMark(frame: frame) }
        if state.waitingForNetwork { return StatusLeadingMark.offlineMark(frame: frame) }
        if state.reconnecting { return StatusLeadingMark.reconnectingMark(frame: frame) }
        if state.connectingMCP { return StatusLeadingMark.connectingMCPMark(frame: frame) }
        return StatusLeadingMark.mark(running: focusedWorks(state), sandboxed: state.sandboxed, frame: frame)
    }

    /// What waits on the person, first: a line a command asked for, and, while a lane is shown, an approval or the model's questions.
    private static func waiting(_ state: ScreenState) -> [StatusSegment] {
        var pieces: [StatusSegment] = []
        if let pending = state.pendingInput {
            pieces.append(StatusSegment(pending.line(typed: state.inputAnswer.text), priority: 100, droppable: false))
        }
        guard let lane = state.lane else { return pieces }
        // In a thread's lane its own questions have the section; what main waits for is said, and Esc goes back to it.
        if lane.isThread {
            if lane.stashedApproval != nil || lane.stashedQuestions != nil {
                pieces.append(
                    StatusSegment("Main is waiting for an answer  Esc returns", priority: 100, droppable: false)
                )
            }
            return pieces
        }
        if let pending = state.pendingApproval {
            pieces.append(
                StatusSegment("\(pending.question)  \(pending.shortcutHint)", priority: 100, droppable: false)
            )
        }
        if let pending = state.pendingQuestions {
            let question = pending.questions[pending.current].question
            pieces.append(
                StatusSegment("The model asks: \(question)  Esc returns to answer", priority: 100, droppable: false)
            )
        }
        return pieces
    }

    /// The pieces, in the order they are shown, each with how long it is worth keeping.
    static func segments(
        for state: ScreenState,
        input: String,
        mark: StatusLeadingMark = StatusLeadingMark(character: "")
    ) -> [StatusSegment] {
        var pieces = waiting(state)
        let labels = labelForms(of: state, mark: mark.character)
        pieces.append(StatusSegment(labels, priority: 90))
        if !state.context.isEmpty { pieces.append(StatusSegment(state.context, priority: 40)) }
        if !state.detail.isEmpty { pieces.append(StatusSegment(state.detail, priority: 20)) }
        if state.quitArmedAt != nil {
            pieces.append(StatusSegment(["press Ctrl+C again to quit", "ctrl+c again to quit"], priority: 80))
        }
        if let armed = state.abortArmedAction {
            pieces.append(
                StatusSegment(["press \(armed) again to abort", "\(armed.lowercased()) again to abort"], priority: 82)
            )
        }
        if state.scrollback > 0 {
            let noun = state.scrollback == 1 ? "line" : "lines"
            pieces.append(StatusSegment("\(state.scrollback) \(noun) below", priority: 60, target: .below))
        }
        // More worth keeping than the label: it says the draft is longer than the box.
        if !input.isEmpty { pieces.append(StatusSegment(input, priority: 95)) }
        pieces += selectionPieces(for: state)
        if state.runnerTree.activeCount > 0 {
            // Threads, then jobs, as the sidebar has them (roadmap 0194).
            let jobs = state.runnerTree.activeJobCount
            let threads = state.runnerTree.activeCount - jobs
            let text = [(threads, "thread"), (jobs, "job")].filter { $0.0 > 0 }
                .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: " · ")
            pieces.append(StatusSegment(text, priority: 50, target: .runners))
        }
        return pieces
    }

    /// What the selection offers, while there is one, and a copy that went wrong. A copy that worked says nothing.
    private static func selectionPieces(for state: ScreenState) -> [StatusSegment] {
        var pieces: [StatusSegment] = []
        let selecting = state.selection != nil || state.inputSelection != nil
        if selecting {
            let cut = state.inputSelection != nil ? " · ctrl+x cut" : ""
            pieces.append(StatusSegment(["ctrl+c copy · esc clear" + cut, "ctrl+c copy"], priority: 30))
        }
        if ClipboardNotice.needsAttention(state.clipboardNotice) {
            pieces.append(StatusSegment(state.clipboardNotice, priority: 70))
        } else if !selecting, state.verbose, !state.nativeSelectionHint.isEmpty {
            pieces.append(StatusSegment(state.nativeSelectionHint, priority: 5))
        }
        return pieces
    }

    /// The label as it is said at each length: prefixed with the leading mark if non-empty.
    private static func labelForms(of state: ScreenState, mark: String) -> [String] {
        let forms = state.labelVariants.isEmpty ? [state.label] : state.labelVariants
        guard !mark.isEmpty else { return forms }
        return forms.map { "\(mark) · \($0)" }
    }

    /// The rows of the open runner strip. Empty when it is closed.
    static func runnerRows(for state: ScreenState, available: Int, columns: Int) -> [Line] {
        RunnerStrip(state, available: available, columns: columns).lines
    }
}
