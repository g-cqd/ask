internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The status line and where its clickable parts sit. Clipping takes the first cells on narrow terminals; the lines below the reader
    /// and the runner count follow the activity, and selection and copy instructions precede usage details.
    static func status(
        for state: ScreenState, input: String = ""
    ) -> (line: Line, runners: Range<Int>?, below: Range<Int>?) {
        let activity = state.running ? "\(state.label) · working… (ctrl+c to stop)" : "\(state.label) · ready"
        var status = input.isEmpty ? activity : input + " · " + activity
        if state.quitArmedAt != nil { status += " · press Ctrl+C again to quit" }
        var runners: Range<Int>?
        var below: Range<Int>?
        if state.scrollback > 0 {
            let start = UnicodeWidth.displayWidth(of: status + " · ")
            let segment = "\(state.scrollback) \(state.scrollback == 1 ? "line" : "lines") below"
            status += " · " + segment
            below = start ..< start + UnicodeWidth.displayWidth(of: segment)
        }
        if !state.runners.isEmpty {
            let count = state.runners.count
            let start = UnicodeWidth.displayWidth(of: status + " · ")
            let segment = "\(count) \(count == 1 ? "job" : "jobs")"
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

    /// The rows of the open runner list: one per runner, then how many more did not fit. Empty when it is closed.
    static func runnerRows(for state: ScreenState, available: Int) -> [Line] {
        guard state.runnersOpen, !state.runners.isEmpty, available > 0 else { return [] }
        let capacity = Swift.min(5, available)
        let shown = state.runners.count > capacity ? capacity - 1 : state.runners.count
        var rows = state.runners.prefix(shown)
            .map {
                Line(text: "\($0.name)  " + $0.detail.replacing("\n", with: " "), style: Style(dim: true))
            }
        if shown < state.runners.count {
            rows.append(Line(text: "… \(state.runners.count - shown) more", style: Style(dim: true)))
        }
        return rows
    }
}
