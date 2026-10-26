internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The status line and where its clickable parts sit. Clipping takes the first cells on narrow terminals; the lines below the reader
    /// and the runner count follow the activity, and selection and copy instructions precede usage details.
    static func status(
        for state: ScreenState, input: String = ""
    ) -> (line: Line, runners: Range<Int>?, below: Range<Int>?) {
        let activity = state.running ? "\(state.label) · working… (ctrl+c to stop)" : "\(state.label) · ready"
        var status = questions(in: state) + (input.isEmpty ? activity : input + " · " + activity)
        if state.quitArmedAt != nil { status += " · press Ctrl+C again to quit" }
        if let lane = state.lane { status += " · main › \(lane.name) · esc returns" }
        var runners: Range<Int>?
        var below: Range<Int>?
        if state.scrollback > 0 {
            let start = UnicodeWidth.displayWidth(of: status + " · ")
            let segment = "\(state.scrollback) \(state.scrollback == 1 ? "line" : "lines") below"
            status += " · " + segment
            below = start ..< start + UnicodeWidth.displayWidth(of: segment)
        }
        if state.runnerTree.activeCount > 0 {
            let count = state.runnerTree.activeCount
            let noun = state.runnerTree.activeJobCount == count ? "job" : "runner"
            let start = UnicodeWidth.displayWidth(of: status + " · ")
            let segment = "\(count) \(noun)\(count == 1 ? "" : "s")"
            status += " · " + segment
            runners = start ..< start + UnicodeWidth.displayWidth(of: segment)
        }
        let selecting = state.selection != nil || state.inputSelection != nil
        if selecting { status += " · ctrl+c copy · esc clear" }
        if state.inputSelection != nil { status += " · ctrl+x cut" }
        if !state.clipboardNotice.isEmpty {
            status += " · " + state.clipboardNotice
        } else if !selecting, !state.nativeSelectionHint.isEmpty {
            status += " · " + state.nativeSelectionHint
        }
        if !state.detail.isEmpty { status += " · " + state.detail }
        return (Line(text: status, style: Style(dim: true)), runners, below)
    }

    /// What leads the line while something waits for an answer, so a narrow screen cuts the rest and not it: a line a command asked for, and an
    /// approval question while a lane hides the main transcript it was put in.
    private static func questions(in state: ScreenState) -> String {
        var text = ""
        if let pending = state.pendingInput { text += pending.line(typed: state.inputAnswer.text) + " · " }
        if state.lane != nil, let pending = state.pendingApproval {
            text = "\(pending.question)  y once · a for this session · n no · " + text
        }
        return text
    }

    /// The rows of the open runner strip. Empty when it is closed.
    static func runnerRows(for state: ScreenState, available: Int, columns: Int) -> [Line] {
        RunnerStrip(state, available: available, columns: columns).lines
    }
}
