internal import TerminalKitText

/// What a frame records of where things are drawn, for clicks, hover and scrolling; apart from ScreenComposer.swift to keep `compose`
/// under the length limit.
extension ScreenComposer {
    /// The heights of what is drawn under the transcript.
    struct BottomRows {
        var columns: Int
        var screen: Int
        var transcript: Int
        var upperRule: Int
        var rules: Int
        var picker: Int
        var pickerRows: Int
        /// The input's rows, or the bottom band's when the sidebar is there (note n39).
        var prompt: Int
        /// The column the input's text starts at: 2 inside the box (note n36), 0 without one.
        var inset = 0

        /// In the order they are drawn, top down; the upper rule is half the rules.
        // swiftlint:disable:next function_parameter_count
        init(
            _ columns: Int,
            _ screen: Int,
            _ transcript: Int,
            _ rules: Int,
            _ picker: Int,
            _ pickerRows: Int,
            _ prompt: Int
        ) {
            self.columns = columns
            self.screen = screen
            self.transcript = transcript
            upperRule = rules / 2
            self.rules = rules
            self.picker = picker
            self.pickerRows = pickerRows
            self.prompt = prompt
        }
    }

    /// The frame's geometry: the transcript's rows, the status line's pieces, the input, the picker, the list under the input, and
    /// the sidebar, beside the transcript or in the bottom band.
    // swiftlint:disable:next function_parameter_count
    func geometry(
        _ state: ScreenState,
        map: RowMap<Int>,
        totalLines: Int,
        layout: BottomRows,
        status: (line: Line, runners: Range<Int>?, below: Range<Int>?),
        editor: PromptLayout.Frame,
        strip: RunnerStrip,
        sidebar: Sidebar,
        inBand: Bool
    ) -> FrameGeometry {
        let promptRow = layout.transcript + layout.upperRule + layout.picker
        var geometry = FrameGeometry(
            rows: map,
            foldBlocks: foldBlocks,
            middleFolds: middleFolds,
            transcriptRows: layout.transcript,
            columns: layout.columns,
            totalLines: totalLines,
            scrollback: state.scrollback,
            statusRow: layout.transcript + layout.rules + layout.picker + layout.prompt,
            runnerColumns: status.runners,
            belowColumns: status.below,
            markColumns: Self.markColumns(for: state),
            promptRow: promptRow,
            promptRows: editor.lines.count,
            promptTop: editor.top,
            prompt: editor.layout
        )
        // The picker opens above the box (note n36): its title on the first row under the transcript, its first match below it.
        .withPicker(state: state, firstRow: layout.transcript + 1, rows: layout.pickerRows)
        geometry.promptColumn = layout.inset
        geometry.links = rowLinks
        geometry.placeStrip(strip, firstRow: layout.screen - strip.lines.count)
        geometry.placeSidebar(sidebar, columns: layout.columns, top: inBand ? promptRow : 0, inBand: inBand)
        return geometry
    }

    /// The list under the input, the hovered runner brightened.
    static func strip(for state: ScreenState, available: Int, columns: Int) -> RunnerStrip {
        var strip = RunnerStrip(state, available: available, columns: columns)
        if case .job(let id) = state.hover, let row = strip.ids.firstIndex(of: id) {
            strip.lines[row] = brightened(strip.lines[row])
        }
        return strip
    }
}
