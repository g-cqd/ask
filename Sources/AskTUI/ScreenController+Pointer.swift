internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// The pointer: the wheel scrolls, a drag selects, a double click takes a word and a triple click a line (TerminalKit roadmap 0016 and
/// 0017). All of it is state in, state and effects out, like the keyboard.
extension ScreenController {
    /// The one region the pointer acts on: the transcript. The prompt and the status line are not content.
    private static let transcriptTarget = 0

    mutating func handle(mouse event: MouseEvent, at now: ContinuousClock.Instant) -> [Effect] {
        guard options.mouse else { return [] }
        var regions = RegionMap<Int>()
        regions.add(
            Self.transcriptTarget, at: CellRect(row: 0, col: 0, rows: frame.transcriptRows, cols: frame.columns))
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
            case .wheel(_, _, let direction, _):
                switch direction {
                    case .up: scroll(by: options.scrollLines)
                    case .down: scroll(by: -options.scrollLines)
                    case .left, .right: break
                }
            case .dragBegan(let target, let origin, .left, _) where target == Self.transcriptTarget:
                _ = selector.beginDrag(row: origin.row, col: origin.col, rows: frame.rows)
            case .dragBegan:
                break
            case .dragMoved(let cell):
                let update = selector.drag(row: cell.row, col: cell.col, rows: frame.rows, scrollableRows: scrollable)
                switch update.scroll {
                    case .up: scroll(by: 1)
                    case .down: scroll(by: -1)
                    case nil: break
                }
            case .dragEnded:
                // Into a local first: `self` is read before an argument is evaluated, so the copy would see the old selection.
                let update = selector.endDrag()
                return copyIfCommitted(update)
            case .click(_, let cell, .left, _, let count):
                let content = count >= 2 ? TranscriptContent(state.transcript) : TranscriptContent()
                let update = selector.click(
                    row: cell.row, col: cell.col, count: count, rows: frame.rows, content: content)
                return copyIfCommitted(update)
            case .click:
                break
        }
        return []
    }

    /// Scrolls the transcript up by `lines`, or down for a negative number, and no further than its ends.
    private mutating func scroll(by lines: Int) {
        let furthest = Swift.max(0, frame.totalLines - frame.transcriptRows)
        state.scrollback = Swift.max(0, Swift.min(state.scrollback + lines, Swift.max(furthest, state.scrollback)))
    }

    private func copyIfCommitted(_ update: SelectionController<Int>.Update) -> [Effect] {
        guard update.committed, options.copyOnSelect,
            let text = selector.selection?.text(in: TranscriptContent(state.transcript)), !text.isEmpty
        else { return [] }
        return [.copy(text)]
    }

    /// Drops the selection and any drag in progress, such as when the user types or the conversation is cleared.
    mutating func clearSelection() {
        selector.clear()
        pointer.reset()
        state.selection = nil
    }
}
