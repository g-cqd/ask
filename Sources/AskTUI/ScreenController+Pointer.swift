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
    /// The approval section's answers, where a click checks one.
    private static let approvalTarget = 6
    /// The approval's command, where a click unfolds it.
    private static let approvalDetailTarget = 7

    mutating func handle(mouse event: MouseEvent, at now: ContinuousClock.Instant) -> [Effect] {
        guard options.mouse else { return [] }
        if hoverMotion(event) { return [] }
        var regions = RegionMap<Int>()
        regions.add(
            Self.transcriptTarget,
            at: CellRect(row: 0, col: 0, rows: frame.transcriptRows, cols: frame.transcriptColumns)
        )
        if frame.prompt != nil, frame.promptRows > 0 {
            regions.add(
                Self.promptTarget,
                at: CellRect(row: frame.promptRow, col: 0, rows: frame.promptRows, cols: frame.columns)
            )
        }
        if frame.runnerColumns != nil || frame.belowColumns != nil || frame.markColumns != nil {
            regions.add(Self.statusTarget, at: CellRect(row: frame.statusRow, col: 0, rows: 1, cols: frame.columns))
        }
        func band(_ target: Int, from row: Int, rows count: Int) {
            if count > 0 { regions.add(target, at: CellRect(row: row, col: 0, rows: count, cols: frame.columns)) }
        }
        band(Self.stripTarget, from: frame.stripFirstRow, rows: frame.stripIDs.count)
        if !frame.sidebarIDs.isEmpty {
            regions.add(
                Self.sidebarTarget,
                at: CellRect(
                    row: frame.sidebarTop,
                    col: frame.sidebarColumn + 1,
                    rows: frame.sidebarIDs.count,
                    cols: Swift.max(0, frame.columns - frame.sidebarColumn - 1)
                )
            )
        }
        if let corner = frame.sidebarCorner {
            // The closed sidebar's toggle, over the transcript's corner: the sidebar's own target, which it opens.
            regions.add(Self.sidebarTarget, at: CellRect(row: 0, col: corner, rows: 1, cols: 1), layer: 1)
        }
        band(Self.approvalTarget, from: frame.approvalAnswers.lowerBound, rows: frame.approvalAnswers.count)
        band(Self.approvalDetailTarget, from: frame.approvalDetail.lowerBound, rows: frame.approvalDetail.count)
        band(Self.pickerTarget, from: frame.pickerFirstRow, rows: frame.pickerWindow.count)
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
                    request: update.scroll,
                    row: cell.row,
                    col: cell.col,
                    extendedAt: state.scrollback
                )
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
            case .click(let target, let cell, .left, _, _)
            where target == Self.approvalTarget || target == Self.approvalDetailTarget:
                clickSection(detail: target == Self.approvalDetailTarget, at: cell)
            case .click(let target, let cell, .left, _, _) where target == Self.sidebarTarget:
                return clickSidebar(row: cell.row - frame.sidebarTop)
            case .click(let target, let cell, .left, _, _) where target == Self.stripTarget:
                return clickStrip(row: cell.row - frame.stripFirstRow)
            case .click(let target, let cell, .left, _, let count) where target == Self.promptTarget:
                if count >= 2 { return selectInput(at: cell, count: count) }
                placeCursor(at: cell)
            // Only inside the transcript's columns: the sidebar's divider is no block's, whatever row it is on (note n27).
            case .click(_, let cell, .left, _, let count) where cell.col < frame.transcriptColumns:
                return clickTranscript(at: cell, count: count)
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

    /// A click on the transcript: a link opens, a selection is let go, a fold control folds, and anything else starts a selection.
    private mutating func clickTranscript(at cell: CellPosition, count: Int) -> [Effect] {
        // A link wins over the fold and the selection; a double click still takes the word.
        if count == 1, let uri = link(at: cell) {
            // A command fills an empty input, ready to run or to finish (note n11); a written one is left as it is.
            guard uri.hasPrefix(PathLinks.commandScheme) else { return [.openLink(uri)] }
            if state.editor.text.isEmpty { state.editor.paste("/\(uri.dropFirst(PathLinks.commandScheme.count)) ") }
            return []
        }
        if count == 1, isSelected(cell) {
            selector.clear()
            return []
        }
        // A thread's fork-point block opens its lane (note n23).
        if let effects = openThread(atRow: cell.row) { return effects }
        // Fold controls toggle at every click count; rapid re-clicks must not become word selection.
        if toggleFold(atRow: cell.row) { return [] }
        let content = count >= 2 ? TranscriptContent(state.transcript) : TranscriptContent()
        let update = selector.click(
            row: cell.row,
            col: cell.col,
            count: count,
            rows: frame.rows,
            content: content
        )
        return copyIfCommitted(update)
    }

    /// The link drawn at `cell` of the transcript, if any.
    func link(at cell: CellPosition) -> String? {
        guard frame.links.indices.contains(cell.row) else { return nil }
        return frame.links[cell.row].first { $0.columns.contains(cell.col) }?.uri
    }

    /// Toggles tools/thinking from any owned row, including padding; code folds still use their fence lines.
    /// The lane of the thread whose fork-point block is on `row`, when it is listed; nil for any other row.
    private mutating func openThread(atRow row: Int) -> [Effect]? {
        guard frame.foldBlocks.indices.contains(row), let block = frame.foldBlocks[row],
            let name = state.transcript.forkBlocks[block],
            let runner = state.runners.first(where: { $0.id == name && $0.kind == .agent })
        else { return nil }
        return enterLane(runner)
    }

    private mutating func toggleFold(atRow row: Int) -> Bool {
        let source = frame.rows.provenance(atRow: row)
        let owned = frame.foldBlocks.indices.contains(row) ? frame.foldBlocks[row] : nil
        guard let block = owned ?? source?.block, state.transcript.items.indices.contains(block)
        else { return false }
        let before =
            ScreenComposer.lines(
                in: state.transcript,
                at: block,
                columns: frame.transcriptColumns,
                style: state.blocks
            )
            .count
        if frame.middleFolds.indices.contains(row), frame.middleFolds[row] {
            state.transcript.toggleCodeFold(Transcript.outputFence, at: block)
        } else if let source, let fence = state.transcript.codeFence(toggledByLine: source.line, at: block) {
            state.transcript.toggleCodeFold(fence, at: block)
        } else if state.transcript.isFoldable(block) {
            state.transcript.toggleFold(block)
        } else {
            return false
        }
        let after =
            ScreenComposer.lines(
                in: state.transcript,
                at: block,
                columns: frame.transcriptColumns,
                style: state.blocks
            )
            .count
        // Scrolled back, the lines below the header grew or shrank, so the view moves by as much and the header stays on its row.
        // At the bottom the view follows the end, as it does for streaming.
        state.scroll.keepPlace(whenRowsAboveChangeBy: after - before)
        // Positions inside a body that just closed no longer exist.
        selector.clear()
        return true
    }
}
