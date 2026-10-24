internal import TerminalKitInput
internal import TerminalKitText

/// A click in the input puts the cursor where it landed, by the same display map the input was drawn with.
extension ScreenController {
    /// Moves the draft's cursor to the character at `cell`, or the nearest one on its row. The selection in the transcript is dropped,
    /// as typing would, and a question waiting for an answer keeps the keys and the pointer to itself.
    mutating func placeCursor(at cell: CellPosition) {
        guard state.pendingApproval == nil, let layout = frame.prompt else { return }
        let row = frame.promptTop + cell.row - frame.promptRow
        clearSelection()
        state.editor.place(cursor: layout.offset(atRow: row, column: cell.col))
    }
}
