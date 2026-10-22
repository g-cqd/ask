internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

extension ScreenController {
    /// Selection gets Ctrl+C and Escape before the editor: copy then clear, or just clear. With no selection the run keeps its
    /// existing interrupt/abort keys. Approval questions are deliberately handled before this path.
    mutating func selectionKey(_ key: KeyEvent) -> [Effect]? {
        guard let selection = selector.selection else { return nil }
        if key.keyCode == 0x1B {
            clearSelection()
            return []
        }
        let isCopy =
            key.keyCode == 0x03 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43))
        guard isCopy else { return nil }
        let text = selection.text(in: TranscriptContent(state.transcript))
        clearSelection()
        guard let text, !text.isEmpty else { return [] }
        return [.copy(text)]
    }

    /// A click on selected text clears it; it must not activate a folded header underneath the selection (roadmap 0051).
    func isSelected(_ cell: CellPosition) -> Bool {
        guard let selection = selector.selection else { return false }
        return frame.rows.highlights(of: selection, in: TranscriptContent(state.transcript))
            .contains {
                $0.row == cell.row && cell.col >= $0.startCol && cell.col < $0.endCol
            }
    }
}
