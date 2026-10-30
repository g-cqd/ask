extension FrameGeometry {
    /// This geometry with the picker's rows in it, when the state shows a picker with matches.
    /// - Parameters:
    ///   - state: what was drawn.
    ///   - firstRow: the row of the first match, under the title.
    ///   - rows: the rows the picker had to draw in, as the composer gave them.
    /// - Returns: the geometry, with the matches' window and word, or unchanged when no match is on the screen.
    func withPicker(state: ScreenState, firstRow: Int, rows: Int) -> FrameGeometry {
        // The section starts where the picker's title would, one row above its first match.
        let top = firstRow - 1
        if let pending = state.pendingApproval {
            let layout = ScreenComposer.approvalLayout(pending, columns: columns, rows: rows)
            return section(answers: layout.answers, detail: layout.detail, top: top)
        }
        if let pending = state.pendingQuestions {
            // The questions use the approval's regions: their choices as its answers, their tab row as its command.
            let layout = ScreenComposer.questionLayout(pending, columns: columns, rows: rows)
            var geometry = section(
                answers: layout.choices, detail: layout.tabs.map { $0 ..< $0 + 1 } ?? 0 ..< 0, top: top)
            geometry.questionTabs = ScreenComposer.questionTabColumns(pending)
            return geometry
        }
        guard let picker = state.picker else { return self }
        var geometry = self
        geometry.pickerWindow = ScreenComposer.window(of: picker, rows: rows)
        geometry.pickerFirstRow = firstRow
        geometry.pickerTrigger = picker.trigger
        return geometry
    }

    /// This geometry with the section's clickable rows, `answers` and `detail` counted from `top`.
    private func section(answers: Range<Int>, detail: Range<Int>, top: Int) -> FrameGeometry {
        var geometry = self
        geometry.approvalAnswers = (top + answers.lowerBound) ..< (top + answers.upperBound)
        geometry.approvalDetail = (top + detail.lowerBound) ..< (top + detail.upperBound)
        return geometry
    }
}
