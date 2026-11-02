internal import TerminalKitCodecs

/// Roadmap 0172: a motion report with no button held moves the hover, and nothing else; the recognizer never sees it, so it selects
/// and drags nothing.
extension ScreenController {
    /// Whether `event` was a motion report, which this has handled.
    mutating func hoverMotion(_ event: MouseEvent) -> Bool {
        // Motion with a button held arrives as a drag, so motion is always the pointer moving with no button down.
        guard event.kind == .motion else { return false }
        state.hover = options.hover ? hovered(row: event.row - 1, col: event.col - 1) : nil
        return true
    }

    /// What a click at `row`, `col` would act on, of what hover shows.
    private func hovered(row: Int, col: Int) -> Hover? {
        if row >= 0, row < frame.transcriptRows, col < frame.transcriptColumns, frame.foldBlocks.indices.contains(row),
            let block = frame.foldBlocks[row]
        {
            return .block(block)
        }
        let strip = row - frame.stripFirstRow
        if strip >= 0, strip < frame.stripIDs.count { return .job(frame.stripIDs[strip]) }
        return nil
    }
}
