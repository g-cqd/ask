extension FrameGeometry {
    /// This geometry with the picker's rows in it, when the state shows a picker with matches.
    /// - Parameters:
    ///   - state: what was drawn.
    ///   - firstRow: the row of the first match, under the title.
    ///   - rows: the rows the picker had to draw in, as the composer gave them.
    /// - Returns: the geometry, with the matches' window and word, or unchanged when no match is on the screen.
    func withPicker(state: ScreenState, firstRow: Int, rows: Int) -> FrameGeometry {
        if let pending = state.pendingApproval {
            var geometry = self
            let answers = ScreenComposer.approvalLayout(pending, columns: columns, rows: rows).answers
            // The section starts where the picker's title would, one row above its first match.
            geometry.approvalAnswers = (firstRow - 1 + answers.lowerBound) ..< (firstRow - 1 + answers.upperBound)
            return geometry
        }
        guard let picker = state.picker else { return self }
        var geometry = self
        geometry.pickerWindow = ScreenComposer.window(of: picker, rows: rows)
        geometry.pickerFirstRow = firstRow
        geometry.pickerTrigger = picker.trigger
        return geometry
    }
}
