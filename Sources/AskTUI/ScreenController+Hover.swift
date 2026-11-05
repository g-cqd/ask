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
        if row == 0, let corner = frame.sidebarCorner, col == corner { return .job(Sidebar.toggleID) }
        if row >= 0, row < frame.transcriptRows, col < frame.transcriptColumns, frame.foldBlocks.indices.contains(row),
            let block = frame.foldBlocks[row]
        {
            return .block(block)
        }
        let sidebarRow = row - frame.sidebarTop
        if sidebarRow >= 0, sidebarRow < frame.sidebarIDs.count, col > frame.sidebarColumn, col < frame.columns {
            return .job(frame.sidebarIDs[sidebarRow])
        }
        let pickerOffset = row - frame.pickerFirstRow
        if pickerOffset >= 0, pickerOffset < frame.pickerWindow.count,
            let picker = state.picker, state.pendingApproval == nil, state.pendingQuestions == nil,
            state.pendingInput == nil
        {
            let index = frame.pickerWindow.lowerBound + pickerOffset
            if picker.matches.indices.contains(index), !picker.matches[index].isHeading {
                return .picker(index)
            }
        }
        let strip = row - frame.stripFirstRow
        if strip >= 0, strip < frame.stripIDs.count { return .job(frame.stripIDs[strip]) }
        return nil
    }
}
