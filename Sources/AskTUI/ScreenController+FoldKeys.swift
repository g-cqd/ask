internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

// The fold keys and what they toggle, and clearing the selection; apart from ScreenController+Pointer.swift
// to keep each file under the 250-line ceiling.
extension ScreenController {
    /// Ctrl+O: what a keyboard has for the click, and for the mouse being off. It flips every tool block at once.
    func isToggleToolOutput(_ key: KeyEvent) -> Bool { Self.isControl(key, "o") }

    /// Ctrl+T: the same for thinking blocks.
    func isToggleThinking(_ key: KeyEvent) -> Bool { Self.isControl(key, "t") }

    /// Ctrl and a letter, as a legacy terminal sends it (the control byte) or a keyboard-protocol terminal does (letter plus modifier).
    static func isControl(_ key: KeyEvent, _ letter: Character) -> Bool {
        guard let code = letter.asciiValue.map(UInt32.init) else { return false }
        return key.keyCode == code & 0x1F || (key.modifiers.contains(.ctrl) && key.keyCode == code)
    }

    mutating func toggleAllThinking() -> [Effect] {
        state.transcript.setThinkingFoldedByDefault(!state.transcript.thinkingFoldedByDefault)
        clearSelection()
        return []
    }

    mutating func toggleAllToolOutput() -> [Effect] {
        state.transcript.setToolsFoldedByDefault(!state.transcript.toolsFoldedByDefault)
        clearSelection()
        return []
    }

    /// Drops the selection and any drag in progress, such as when the user types or the conversation is cleared.
    mutating func clearSelection() {
        dropSelections()
        pointer.reset()
    }

    /// Drops both selections but leaves the pointer's memory of its last click alone: a click that changes the selection is part of a
    /// double or triple click, and forgetting it would make the next click a first one again.
    mutating func dropSelections() {
        state.clipboardNotice = ""
        selector.clear()
        autoscroll.request = nil
        state.selection = nil
        state.inputSelection = nil
        state.promptScroll = nil
        inputDrag = InputDrag()
        inputAnchor = nil
    }
}
