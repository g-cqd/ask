internal import TerminalKitText

/// Edge autoscroll (roadmap 0051). A drag held at an edge scrolls one line a tick, and the selection follows the newly shown line.
extension ScreenController {
    /// Whether the driver should be ticking: a drag is held at an edge and either more transcript lies that way or the line that
    /// last scrolled into view is not yet in the selection.
    var isAutoscrolling: Bool {
        guard options.mouse, selector.isDragging, let request = autoscroll.request else { return false }
        return canScroll(request) || autoscroll.extendedAt != state.scrollback
    }

    private func canScroll(_ request: ScrollRequest) -> Bool {
        switch request {
            case .up: frame.totalLines - frame.transcriptRows > state.scrollback
            case .down: state.scrollback > 0
        }
    }

    /// One timer step. It acts only on a frame that shows the current scroll position, so it extends the selection over the line
    /// that scrolled into view and never over a position it has not seen; a frame still being drawn makes it wait for the next tick.
    /// - Returns: whether the transcript or the selection changed, so the screen should be drawn.
    mutating func tick() -> Bool {
        guard isAutoscrolling, let request = autoscroll.request, frame.scrollback == state.scrollback else {
            return false
        }
        let before = (state.scrollback, selector.selection)
        if autoscroll.extendedAt != state.scrollback {
            let update = selector.drag(
                row: autoscroll.row, col: autoscroll.col, rows: frame.rows, scrollableRows: 0 ..< frame.transcriptRows)
            state.selection = selector.selection
            autoscroll.request = update.scroll
            autoscroll.extendedAt = state.scrollback
        }
        if canScroll(request) { scroll(by: request == .up ? 1 : -1) }
        return before.0 != state.scrollback || before.1 != selector.selection
    }
}
