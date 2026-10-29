internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// The pointer: the wheel scrolls, a drag selects, a double click takes a word and a triple click a line (TerminalKit roadmap 0016 and
/// 0017). All of it is state in, state and effects out, like the keyboard.
extension ScreenController {
    /// The one region the pointer acts on: the transcript. The prompt and the status line are not content.
    private static let transcriptTarget = 0
    /// The status line, which acts only on its runner count.
    private static let statusTarget = 1
    /// The rows of the picker's matches, which a click chooses from.
    private static let pickerTarget = 2
    /// The input, where a click puts the cursor.
    private static let promptTarget = 3
    /// The runner strip's rows, where a click focuses a runner.
    private static let stripTarget = 4
    /// The sidebar's rows, where a click focuses a runner.
    private static let sidebarTarget = 5

    mutating func handle(mouse event: MouseEvent, at now: ContinuousClock.Instant) -> [Effect] {
        guard options.mouse else { return [] }
        var regions = RegionMap<Int>()
        regions.add(
            Self.transcriptTarget,
            at: CellRect(row: 0, col: 0, rows: frame.transcriptRows, cols: frame.transcriptColumns))
        if frame.prompt != nil, frame.promptRows > 0 {
            regions.add(
                Self.promptTarget,
                at: CellRect(row: frame.promptRow, col: 0, rows: frame.promptRows, cols: frame.columns))
        }
        if frame.runnerColumns != nil || frame.belowColumns != nil || frame.markColumns != nil {
            regions.add(Self.statusTarget, at: CellRect(row: frame.statusRow, col: 0, rows: 1, cols: frame.columns))
        }
        if !frame.stripIDs.isEmpty {
            regions.add(
                Self.stripTarget,
                at: CellRect(row: frame.stripFirstRow, col: 0, rows: frame.stripIDs.count, cols: frame.columns))
        }
        if !frame.sidebarIDs.isEmpty {
            regions.add(
                Self.sidebarTarget,
                at: CellRect(
                    row: 0, col: frame.transcriptColumns + 1, rows: frame.sidebarIDs.count,
                    cols: Swift.max(0, frame.columns - frame.transcriptColumns - 1)))
        }
        if !frame.pickerWindow.isEmpty {
            regions.add(
                Self.pickerTarget,
                at: CellRect(row: frame.pickerFirstRow, col: 0, rows: frame.pickerWindow.count, cols: frame.columns))
        }
        // Collected first: acting on an event changes the controller, which the recognizer is part of.
        var events: [PointerEvent<Int>] = []
        pointer.handle(event, at: now, in: regions) { events.append($0) }
        var effects: [Effect] = []
        for event in events { effects += act(on: event) }
        state.selection = selector.selection
        return effects
    }

    private mutating func act(on event: PointerEvent<Int>) -> [Effect] {
        let scrollable = 0 ..< frame.transcriptRows
        switch event {
            case .wheel(let target, _, let direction, _):
                wheel(direction, over: target)
            case .dragBegan(let target, let origin, .left, _) where target == Self.transcriptTarget:
                state.clipboardNotice = ""
                _ = selector.beginDrag(row: origin.row, col: origin.col, rows: frame.rows)
            case .dragBegan(let target, let origin, .left, _) where target == Self.promptTarget:
                state.clipboardNotice = ""
                beginInputDrag(at: origin)
            case .dragBegan:
                break
            case .dragMoved(let cell) where inputDrag.isActive:
                moveInputDrag(to: cell)
            case .dragEnded where inputDrag.isActive:
                return endInputDrag()
            case .dragMoved(let cell):
                let update = selector.drag(row: cell.row, col: cell.col, rows: frame.rows, scrollableRows: scrollable)
                autoscroll = DragAutoscroll(
                    request: update.scroll, row: cell.row, col: cell.col, extendedAt: state.scrollback)
                switch update.scroll {
                    case .up: scroll(by: 1)
                    case .down: scroll(by: -1)
                    case nil: break
                }
            case .dragEnded:
                autoscroll.request = nil
                // Into a local first: `self` is read before an argument is evaluated, so the copy would see the old selection.
                let update = selector.endDrag()
                return copyIfCommitted(update)
            // Any count: a second click is the same row, or no row at all once the first has closed the list.
            case .click(let target, let cell, .left, _, _) where target == Self.pickerTarget:
                return clickPicker(match: frame.pickerWindow.lowerBound + cell.row - frame.pickerFirstRow)
            // Any count: a second click inside the double-click time is the user closing what the first opened, not selecting a word.
            case .click(let target, let cell, .left, _, _) where target == Self.statusTarget:
                if frame.belowColumns?.contains(cell.col) == true {
                    state.scrollback = 0
                    return []
                }
                if frame.markColumns?.contains(cell.col) == true { return toggleSandboxNote() }
                guard frame.runnerColumns?.contains(cell.col) == true else { return [] }
                return toggleRunners()
            case .click(let target, let cell, .left, _, _) where target == Self.sidebarTarget:
                return clickSidebar(row: cell.row)
            case .click(let target, let cell, .left, _, _) where target == Self.stripTarget:
                return clickStrip(row: cell.row - frame.stripFirstRow)
            case .click(let target, let cell, .left, _, let count) where target == Self.promptTarget:
                if count >= 2 { return selectInput(at: cell, count: count) }
                placeCursor(at: cell)
            case .click(_, let cell, .left, _, let count):
                if count == 1, isSelected(cell) {
                    selector.clear()
                    return []
                }
                // Fold controls toggle at every click count; rapid re-clicks must not become word selection.
                if toggleFold(atRow: cell.row) { return [] }
                let content = count >= 2 ? TranscriptContent(state.transcript) : TranscriptContent()
                let update = selector.click(
                    row: cell.row, col: cell.col, count: count, rows: frame.rows, content: content)
                return copyIfCommitted(update)
            case .click:
                break
        }
        return []
    }

    /// One step of the wheel: over a tall input it scrolls the input's window; anywhere else it scrolls the transcript.
    private mutating func wheel(_ direction: WheelDirection, over target: Int?) {
        if target == Self.promptTarget, scrollInput(direction) { return }
        switch direction {
            case .up: scroll(by: options.scrollLines)
            case .down: scroll(by: -options.scrollLines)
            case .left, .right: break
        }
    }

    /// Scrolls the transcript up by `lines`, or down for a negative number, and no further than its ends.
    mutating func scroll(by lines: Int) {
        state.scroll.scroll(by: lines, totalRows: frame.totalLines, viewportRows: frame.transcriptRows)
    }

    private func copyIfCommitted(_ update: SelectionController<Int>.Update) -> [Effect] {
        guard update.committed, options.copyOnSelect,
            let text = selector.selection?.text(in: TranscriptContent(state.transcript)), !text.isEmpty
        else { return [] }
        return [.copy(text)]
    }

    /// Toggles tools/thinking from any owned row, including padding; code folds still use their fence lines.
    private mutating func toggleFold(atRow row: Int) -> Bool {
        let source = frame.rows.provenance(atRow: row)
        let owned = frame.foldBlocks.indices.contains(row) ? frame.foldBlocks[row] : nil
        guard let block = owned ?? source?.block, state.transcript.items.indices.contains(block)
        else { return false }
        let before =
            ScreenComposer.lines(
                in: state.transcript, at: block, columns: frame.transcriptColumns, style: state.blocks
            )
            .count
        if let source, let fence = state.transcript.codeFence(toggledByLine: source.line, at: block) {
            state.transcript.toggleCodeFold(fence, at: block)
        } else if state.transcript.isFoldable(block) {
            state.transcript.toggleFold(block)
        } else {
            return false
        }
        let after =
            ScreenComposer.lines(
                in: state.transcript, at: block, columns: frame.transcriptColumns, style: state.blocks
            )
            .count
        // Scrolled back, the lines below the header grew or shrank, so the view moves by as much and the header stays on its row.
        // At the bottom the view follows the end, as it does for streaming.
        state.scroll.keepPlace(whenRowsAboveChangeBy: after - before)
        // Positions inside a body that just closed no longer exist.
        selector.clear()
        return true
    }

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
