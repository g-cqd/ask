internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The status line, fitted to `columns`, and where its clickable parts sit. Each piece is whole, shorter or gone, never cut (roadmap 0074).
    /// It says nothing that conveys nothing: no "ready", no sandbox when there is one (a warning mark leads the label when there is none),
    /// and a copy only when it went wrong.
    static func status(
        for state: ScreenState, input: String = "", columns: Int = 200
    ) -> (line: Line, runners: Range<Int>?, below: Range<Int>?) {
        StatusLine(segments(for: state, input: input), columns: columns).line(style: Style(dim: true))
    }

    /// The pieces, in the order they are shown, each with how long it is worth keeping.
    static func segments(for state: ScreenState, input: String) -> [StatusSegment] {
        var pieces: [StatusSegment] = []
        if let pending = state.pendingInput {
            pieces.append(StatusSegment(pending.line(typed: state.inputAnswer.text), priority: 100, droppable: false))
        }
        if state.lane != nil, let pending = state.pendingApproval {
            pieces.append(
                StatusSegment(
                    "\(pending.question)  y once · a for this session · n no", priority: 100, droppable: false))
        }
        pieces.append(StatusSegment(labelForms(of: state), priority: 90))
        if !state.context.isEmpty { pieces.append(StatusSegment(state.context, priority: 40)) }
        if !state.detail.isEmpty { pieces.append(StatusSegment(state.detail, priority: 20)) }
        if state.running {
            pieces.append(StatusSegment(["working… (ctrl+c to stop)", "working…"], priority: 85))
        }
        if state.quitArmedAt != nil {
            pieces.append(StatusSegment(["press Ctrl+C again to quit", "ctrl+c again to quit"], priority: 80))
        }
        if let lane = state.lane {
            pieces.append(StatusSegment(["main › \(lane.name) · esc returns", "main › \(lane.name)"], priority: 65))
        }
        if state.scrollback > 0 {
            let noun = state.scrollback == 1 ? "line" : "lines"
            pieces.append(StatusSegment("\(state.scrollback) \(noun) below", priority: 60, target: .below))
        }
        if state.runnerTree.activeCount > 0 {
            let count = state.runnerTree.activeCount
            let noun = state.runnerTree.activeJobCount == count ? "job" : "runner"
            pieces.append(StatusSegment("\(count) \(noun)\(count == 1 ? "" : "s")", priority: 50, target: .runners))
        }
        // More worth keeping than the label: it says the draft is longer than the box.
        if !input.isEmpty { pieces.append(StatusSegment(input, priority: 95)) }
        pieces += selectionPieces(for: state)
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

    /// The label as it is said at each length: the screen's own when the conversation gave none.
    private static func labelForms(of state: ScreenState) -> [String] {
        state.labelVariants.isEmpty ? [state.label] : state.labelVariants
    }

    /// The rows of the open runner strip. Empty when it is closed.
    static func runnerRows(for state: ScreenState, available: Int, columns: Int) -> [Line] {
        RunnerStrip(state, available: available, columns: columns).lines
    }
}
