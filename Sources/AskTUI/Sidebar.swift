internal import TerminalKitStyle
internal import TerminalKitText

/// The runner sidebar, character layout (roadmap 0062, step 4): the same tree as the strip, in a column beside the transcript rows, behind a divider.
/// It takes the width only when the screen has room for it, so a narrow terminal keeps its whole transcript.
struct Sidebar {
    /// What one transcript row carries on its right: the divider, then this text.
    struct Cell: Equatable {
        var text: String
        var style: Style
        /// The column of the divider.
        var column: Int
    }

    /// The least screen width that has room for the transcript and the sidebar.
    static let minimumColumns = 70

    /// The panel's width, not counting the divider; 0 when there is none.
    private(set) var width = 0
    /// One cell per transcript row, from the top.
    private(set) var cells: [Cell] = []
    /// The runner each of the first rows shows, for a click.
    private(set) var ids: [String] = []

    /// The width left for the transcript.
    func transcriptColumns(of columns: Int) -> Int { width == 0 ? columns : columns - width - 1 }

    /// - Parameters:
    ///   - state: what the screen holds.
    ///   - columns: the screen width.
    ///   - rows: the transcript's height, which the panel shares.
    init(_ state: ScreenState, columns: Int, rows: Int) {
        guard state.sidebarOpen, columns >= Self.minimumColumns, rows >= 3 else { return }
        width = Swift.min(32, Swift.max(20, columns / 4))
        let tree = RunnerStrip(state, available: rows, columns: width, capacity: rows, requiresOpen: false)
        let lines = tree.lines.isEmpty ? [ScreenComposer.Line(text: "no runners", style: Style(dim: true))] : tree.lines
        let column = columns - width - 1
        cells = (0 ..< rows)
            .map { row in
                guard row < lines.count else { return Cell(text: "", style: .default, column: column) }
                // One column of air after the divider.
                let clipped = " " + ColumnSlicer.split(lines[row].text, columns: 0 ..< width - 1).selected
                return Cell(text: clipped, style: lines[row].style, column: column)
            }
        ids = tree.ids
    }
}
