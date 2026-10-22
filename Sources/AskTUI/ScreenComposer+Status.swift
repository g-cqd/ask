internal import TerminalKitStyle

extension ScreenComposer {
    /// Clipping takes the first cells on narrow terminals; selection/copy instructions still precede usage details.
    static func statusLine(for state: ScreenState, input: String = "") -> Line {
        let activity = state.running ? "\(state.label) · working… (esc to abort)" : "\(state.label) · ready"
        var status = input.isEmpty ? activity : input + " · " + activity
        if state.selection != nil { status += " · ctrl+c copy · esc clear" }
        if !state.clipboardNotice.isEmpty {
            status += " · " + state.clipboardNotice
        } else if state.selection == nil, !state.nativeSelectionHint.isEmpty {
            status += " · " + state.nativeSelectionHint
        }
        if !state.detail.isEmpty { status += " · " + state.detail }
        return Line(text: status, style: Style(dim: true))
    }
}
