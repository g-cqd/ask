internal import TerminalKitStyle

extension ScreenComposer {
    /// Selection instructions and copy routing take priority over usage details, so a narrow status line still explains the action.
    static func statusLine(for state: ScreenState) -> Line {
        let activity = state.running ? "\(state.label) · working… (esc to abort)" : "\(state.label) · ready"
        var status = activity
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
