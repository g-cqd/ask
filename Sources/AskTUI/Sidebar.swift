internal import TerminalKitStyle
internal import TerminalKitText

/// The runner sidebar, character layout (roadmap 0062, step 4; sections, roadmap 0194; steadiness, note n24): beside the transcript,
/// behind a divider. Its first row holds only the toggle, in the screen's top-right corner; then the main conversation, always, with its
/// threads as a tree, and the jobs; its last row says what is running. Each runner is one row: a state mark, the name and what it is
/// doing, and how long an active one has run. It takes the width only when the screen has room for it, so a narrow terminal keeps its
/// whole transcript; while it is closed but would fit, the corner keeps the toggle that opens it.
struct Sidebar {
    /// What one transcript row carries on its right: the divider, unless it is the closed panel's corner, then this text.
    struct Cell: Equatable {
        var text: String
        var style: Style
        /// The column of the divider, or of the text when there is none.
        var column: Int
        var divider = true
    }

    /// The least screen width that has room for the transcript and the sidebar.
    static let minimumColumns = 70
    /// The id of the toggle's row, which a click on closes the panel, as the corner does that opens it.
    static let toggleID = "\u{1}sidebar"
    /// The toggle: the panel goes to the right, or comes back from it.
    static let closeMark = "»"
    static let openMark = "«"

    /// The panel's width, not counting the divider; 0 when there is none.
    private(set) var width = 0
    /// What each transcript row carries on its right, from the top: every row while open, only the corner while closed.
    private(set) var cells: [Cell?] = []
    /// The runner each of the first rows shows, for a click and the hover: the toggle first, "" for a heading, a gap or the counts.
    private(set) var ids: [String] = []
    /// The column of the closed panel's corner toggle, nil while open or when the screen is too narrow for a panel.
    private(set) var cornerColumn: Int?

    /// The width left for the transcript.
    func transcriptColumns(of columns: Int) -> Int { width == 0 ? columns : columns - width - 1 }

    /// - Parameters:
    ///   - state: what the screen holds.
    ///   - columns: the screen width.
    ///   - rows: the transcript's height, which the panel shares.
    init(_ state: ScreenState, columns: Int, rows: Int) {
        guard columns >= Self.minimumColumns, rows >= 3 else { return }
        guard state.sidebarOpen else {
            // A space before the mark, so it never reads as part of the transcript's top row.
            cornerColumn = columns - 1
            let hovered = state.hover == .job(Self.toggleID)
            cells =
                [
                    Cell(
                        text: " " + Self.openMark,
                        style: Style(bold: hovered, dim: !hovered),
                        column: columns - 2,
                        divider: false
                    )
                ]
                + Array(repeating: nil, count: rows - 1)
            return
        }
        width = Swift.min(36, Swift.max(22, columns / 4))
        // One column of air after the divider.
        let inner = width - 1
        let made = SidebarEntries(state, columns: inner)
        let toggle = SidebarEntries.Entry(
            text: String(repeating: " ", count: inner - 1) + Self.closeMark,
            style: Style(dim: true),
            id: Self.toggleID
        )
        let entries =
            [toggle] + Self.window(made.entries, rows: rows - 2, selected: state.stripSelection) + [made.counts]
        let column = columns - width - 1
        let body = entries.count - 1
        cells = (0 ..< rows)
            .map { row in
                // The counts keep the last row, whatever the list above them holds.
                let index = row == rows - 1 ? body : row < body ? row : nil
                guard let index else { return Cell(text: "", style: .default, column: column) }
                var entry = entries[index]
                if case .job(let id) = state.hover, id == entry.id, !id.isEmpty {
                    entry.style.dim = false
                    entry.style.bold = true
                }
                return Cell(
                    text: " " + ColumnSlicer.split(entry.text, columns: 0 ..< inner).selected,
                    style: entry.style,
                    column: column
                )
            }
        ids = (0 ..< rows).map { row in row < body ? entries[row].id : "" }
    }

    /// Whether the panel is drawn: open, and the screen wide enough for it.
    static func isShown(_ state: ScreenState, columns: Int) -> Bool { state.sidebarOpen && columns >= minimumColumns }

    /// At most `rows` entries: from the top, moved down far enough to keep the selected runner shown, the last row saying how many more.
    static func window(_ entries: [SidebarEntries.Entry], rows: Int, selected: String?) -> [SidebarEntries
        .Entry]
    {
        guard entries.count > rows else { return entries }
        let shown = Swift.max(0, rows - 1)
        let chosen = selected.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        let first = Swift.max(0, Swift.min(chosen - shown + 1, entries.count - shown))
        let rest = entries.count - shown
        return Array(entries[first ..< first + shown]) + [.init(text: "… \(rest) more", style: Style(dim: true))]
    }
}
