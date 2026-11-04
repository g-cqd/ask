internal import TerminalKitStyle
internal import TerminalKitText

/// The runner sidebar, character layout (roadmap 0062, step 4; sections, roadmap 0194): beside the transcript, behind a divider, two
/// sections of one row per runner. Threads is a tree rooted at the main conversation; Jobs lists the background commands. Each row is
/// a state mark, the name and what it is doing, and how long an active one has run. It takes the width only when the screen has room
/// for it, so a narrow terminal keeps its whole transcript.
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
    /// The runner each of the first rows shows, for a click and the hover; "" for a heading or a gap.
    private(set) var ids: [String] = []

    /// The width left for the transcript.
    func transcriptColumns(of columns: Int) -> Int { width == 0 ? columns : columns - width - 1 }

    /// - Parameters:
    ///   - state: what the screen holds.
    ///   - columns: the screen width.
    ///   - rows: the transcript's height, which the panel shares.
    init(_ state: ScreenState, columns: Int, rows: Int) {
        guard state.sidebarOpen, columns >= Self.minimumColumns, rows >= 3 else { return }
        width = Swift.min(36, Swift.max(22, columns / 4))
        // One column of air after the divider.
        let inner = width - 1
        var entries = SidebarEntries(state, columns: inner).entries
        if entries.isEmpty { entries = [.init(text: "No threads or jobs", style: Style(dim: true))] }
        entries = Self.window(entries, rows: rows, selected: state.stripSelection)
        let column = columns - width - 1
        cells = (0 ..< rows)
            .map { row in
                guard row < entries.count else { return Cell(text: "", style: .default, column: column) }
                var entry = entries[row]
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
        ids = entries.map(\.id)
    }

    /// At most `rows` entries: from the top, moved down far enough to keep the selected runner shown, the last row saying how many more.
    private static func window(_ entries: [SidebarEntries.Entry], rows: Int, selected: String?) -> [SidebarEntries
        .Entry]
    {
        guard entries.count > rows else { return entries }
        let shown = rows - 1
        let chosen = selected.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        let first = Swift.max(0, Swift.min(chosen - shown + 1, entries.count - shown))
        let rest = entries.count - shown
        return Array(entries[first ..< first + shown]) + [.init(text: "… \(rest) more", style: Style(dim: true))]
    }
}
