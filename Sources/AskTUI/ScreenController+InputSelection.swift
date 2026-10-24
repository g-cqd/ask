internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// Selecting text in the input with the pointer: a drag highlights it, the cursor follows the end being dragged, a drag held at the
/// first or last drawn row steps a row a tick, and typing or deleting replaces what is selected (roadmap 0051, ADR-0072).
extension ScreenController {
    // MARK: - Pointer

    /// The offsets of the character under `cell`: before it and after it. `offset(atRow:column:)` already gives the caret *at or before*
    /// the cell, so the character is the one after that caret, unless that is a line break or the end of the draft: a cell past the end
    /// of a line is then on no character, and its two offsets are one. (A cell on the prefix maps to the first character, which only
    /// matters for a press, and a press at offset 0 can never be the later end of a backward drag.)
    private func inputOffsets(at cell: CellPosition) -> (before: Int, after: Int)? {
        guard let layout = frame.prompt, frame.promptRows > 0 else { return nil }
        let drawn = Swift.min(Swift.max(cell.row - frame.promptRow, 0), frame.promptRows - 1)
        let before = layout.offset(atRow: frame.promptTop + drawn, column: cell.col)
        let characters = state.editor.text
        guard before < characters.count else { return (before, before) }
        let isBreak = characters[characters.index(characters.startIndex, offsetBy: before)].isNewline
        return (before, isBreak ? before : before + 1)
    }

    /// A double click takes the run of like characters under the cell and a triple click the whole hard line, by the rules the
    /// transcript's selection uses (letters, digits and `_` together, spaces together, anything else together). The cursor goes to the
    /// end of what was taken, and it is copied if `ui.copyOnSelect` is on. An empty line has nothing to take.
    mutating func selectInput(at cell: CellPosition, count: Int) -> [Effect] {
        guard state.pendingApproval == nil, let before = inputOffsets(at: cell)?.before else { return [] }
        dropSelections()
        let lines = state.editor.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var start = 0
        var index = 0
        while index < lines.count - 1, before >= start + lines[index].count + 1 {
            start += lines[index].count + 1
            index += 1
        }
        let content = TranscriptContent(blocks: [lines])
        let position = ContentPosition(block: 0, line: index, offset: before - start)
        let taken =
            count == 2
            ? ContentSelection.word(at: position, in: content) : ContentSelection.line(at: position, in: content)
        guard let taken else { return [] }
        let range = start + taken.anchor.offset ..< start + taken.head.offset
        state.inputSelection = range
        state.editor.place(cursor: range.upperBound)
        guard options.copyOnSelect, let text = selectedInputText, !text.isEmpty else { return [] }
        return [.copy(text)]
    }

    mutating func beginInputDrag(at cell: CellPosition) {
        guard state.pendingApproval == nil, let offsets = inputOffsets(at: cell) else { return }
        selector.clear()
        state.inputSelection = nil
        inputDrag = InputDrag(
            isActive: true, anchorBefore: offsets.before, anchorAfter: offsets.after, headBefore: offsets.before,
            headAfter: offsets.after, press: cell)
    }

    mutating func moveInputDrag(to cell: CellPosition) {
        guard inputDrag.isActive, let offsets = inputOffsets(at: cell) else { return }
        if inputDrag.press == cell { return }
        inputDrag.press = nil
        follow(offsets, column: cell.col)
        guard let layout = frame.prompt else { return }
        let row = layout.position(at: inputDrag.headBefore).row
        let top = frame.promptRow
        let bottom = frame.promptRow + frame.promptRows - 1
        inputDrag.request =
            cell.row <= top && row > 0 ? .up : (cell.row >= bottom && row < layout.rows.count - 1 ? .down : nil)
    }

    /// Moves the head, the selection and the cursor, which keeps the head in the drawn window.
    private mutating func follow(_ offsets: (before: Int, after: Int), column: Int) {
        inputDrag.headBefore = offsets.before
        inputDrag.headAfter = offsets.after
        inputDrag.column = column
        state.inputSelection = inputDrag.range
        state.editor.place(cursor: inputDrag.cursor)
    }

    /// Ends the drag. A selection that covers something is complete and may be copied.
    mutating func endInputDrag() -> [Effect] {
        guard inputDrag.isActive else { return [] }
        inputDrag.isActive = false
        inputDrag.request = nil
        guard options.copyOnSelect, let text = selectedInputText, !text.isEmpty else { return [] }
        return [.copy(text)]
    }

    /// One timer step: the head moves a display row toward the edge, at the column it had.
    mutating func stepInputDrag() -> Bool {
        guard inputDrag.isActive, let request = inputDrag.request, let layout = frame.prompt else { return false }
        let row = layout.position(at: inputDrag.headBefore).row + (request == .up ? -1 : 1)
        guard layout.rows.indices.contains(row) else {
            inputDrag.request = nil
            return false
        }
        let before = layout.offset(atRow: row, column: inputDrag.column)
        let moved = inputDrag.headBefore != before
        follow((before, before), column: inputDrag.column)
        return moved
    }

    // MARK: - What is selected

    var selectedInputText: String? {
        guard let range = state.inputSelection else { return nil }
        let text = state.editor.text
        let upper = Swift.min(range.upperBound, text.count)
        guard range.lowerBound < upper else { return nil }
        return String(
            text[
                text.index(text.startIndex, offsetBy: range.lowerBound) ..< text.index(text.startIndex, offsetBy: upper)
            ])
    }

    /// Deletes what is selected, so what is typed or pasted replaces it. Returns whether anything was.
    @discardableResult
    mutating func removeInputSelection() -> Bool {
        guard let range = state.inputSelection else { return false }
        state.inputSelection = nil
        inputDrag = InputDrag()
        state.editor.remove(range)
        return true
    }

    // MARK: - Keys

    /// A selection in the input takes Ctrl+C (copy, then clear) and Escape (clear) before the editor, deletes on Backspace, and is
    /// replaced by typing; any other key just drops it. Nil when there is no selection, or the key goes on to the editor.
    mutating func inputSelectionKey(_ key: KeyEvent) -> [Effect]? {
        guard state.inputSelection != nil else { return nil }
        if key.keyCode == 0x1B {
            clearSelection()
            return []
        }
        if Self.isControl(key, "c") {
            let text = selectedInputText
            clearSelection()
            return text.map { [.copy($0)] } ?? []
        }
        if PromptEditor.isDeletion(key) {
            removeInputSelection()
            return []
        }
        if PromptEditor.insertsText(key) { removeInputSelection() }
        clearSelection()
        return nil
    }
}
