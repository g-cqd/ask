internal import TerminalKitText

/// A reader who scrolled back is reading something, and text that arrives below must not slide it away (ADR-0072).
extension ScreenController {
    /// Runs `change`, then moves the scroll position by the lines it added to the transcript's tail, so the same lines stay on the screen.
    ///
    /// Only a reader who is scrolled back pays: at the end the screen follows the end, and nothing here runs. What is measured is the
    /// block that was last and everything after it, at the width of the last frame, as the composer will wrap it. A change that sets
    /// the scroll position itself (a question that sends the reader to the end, a cleared conversation) is left alone.
    /// - Parameter change: the update to apply.
    /// - Returns: what `change` returned.
    mutating func holdingView(_ change: (inout ScreenController) -> [Effect]) -> [Effect] {
        let held = state.scrollback
        guard held > 0, frame.transcriptColumns > 0 else { return change(&self) }
        let first = Swift.max(0, state.transcript.items.count - 1)
        let before = wrappedLines(from: first)
        let effects = change(&self)
        if state.scrollback == held {
            state.scroll.keepPlace(whenRowsAboveChangeBy: wrappedLines(from: first) - before)
        }
        return effects
    }

    /// How many rows blocks `first` and after take at the last frame's width; none when the transcript no longer reaches `first`.
    private func wrappedLines(from first: Int) -> Int {
        (first ..< Swift.max(first, state.transcript.items.count))
            .reduce(0) {
                $0
                    + ScreenComposer.lines(
                        in: state.transcript, at: $1, columns: frame.transcriptColumns, style: state.blocks
                    )
                    .count
            }
    }
}
