internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// Routing an input event to whichever part of the screen has the keys.
extension ScreenController {
    /// A key for whatever is waiting on the person, before anything else may have it: an approval takes every key (roadmap 0019),
    /// the model's questions the keys they use (the rest type the note, roadmap 0117), a line a command asked for every key.
    private mutating func questionedKey(_ key: KeyEvent) -> [Effect]? {
        if state.pendingApproval != nil { return answer(key) }
        if let effects = questionKey(key) { return effects }
        if state.pendingInput != nil { return answerInput(key) }
        return nil
    }

    mutating func route(
        _ event: InputEvent, pageRows: Int, at now: ContinuousClock.Instant, columns: Int?
    ) -> [Effect] {
        switch event {
            case .key(let key):
                // Any key but the second Ctrl+C ends the quit window (roadmap 0064): what was armed is read here, then cleared.
                let armedAt = state.quitArmedAt
                state.quitArmedAt = nil
                let tappedAt = state.rightTappedAt
                state.rightTappedAt = nil
                if key.keyCode == Key.pageUp.rawValue {
                    // No further than the first line at the top of the screen, as the wheel (roadmap 0125).
                    scroll(by: Swift.max(1, pageRows))
                    return []
                }
                if key.keyCode == Key.pageDown.rawValue {
                    scroll(by: -Swift.max(1, pageRows))
                    return []
                }
                // End goes to the end of the conversation when there is no draft for it to go to the end of (ADR-0072).
                if key.keyCode == Key.end.rawValue, state.scrollback > 0, state.editor.text.isEmpty {
                    state.scroll.followEnd()
                    return []
                }
                if let effects = questionedKey(key) { return effects }
                // A configuration editor is modal: it takes every key, including keys another list would edit with.
                if case .config = state.picker?.kind {
                    return pickerKey(key, screenRows: pageRows + 3) ?? []
                }
                if let effects = selectionOrToggleKey(key, columns: columns) { return effects }
                if let effects = pickerKey(key, screenRows: pageRows + 3) { return effects }
                if let effects = stripKey(key) { return effects }
                clearSelection()
                if let effects = continueTap(key, at: now, previous: tappedAt) { return effects }
                return edit(key, columns: columns, interrupt: Interrupt(at: now, armedAt: armedAt))
            case .mouse(let mouse):
                return handle(mouse: mouse, at: now)
            case .paste(let text) where state.pendingInput != nil:
                state.inputAnswer.paste(text.filter { !$0.isNewline })
                return []
            case .paste where state.picker?.kind.isConfig == true:
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
}
