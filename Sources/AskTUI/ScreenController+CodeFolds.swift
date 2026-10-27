internal import TerminalKitCodecs

/// Long code blocks: Ctrl+G opens or folds them all, and the screen's height caps how long a block may be before it folds.
extension ScreenController {
    /// Ctrl+G, the keyboard's way to every long code block, and the only way with the mouse off.
    func isToggleCode(_ key: KeyEvent) -> Bool { Self.isControl(key, "g") }

    mutating func toggleAllCode() -> [Effect] {
        state.transcript.setCodeFoldedByDefault(!state.transcript.codeFoldedByDefault)
        clearSelection()
        return []
    }

    /// Tells the controller how tall the screen is: a code block never needs more than half of it before it folds (ADR-0046).
    public mutating func setScreenRows(_ rows: Int) {
        pickerScreenRows = rows
        state.transcript.setCodeFoldLines(Swift.min(options.codeFoldLines, Swift.max(1, rows / 2)))
    }
}
