/// The sidebar in the bottom band (notes n39, n40; `ui.sidebarLayout`): beside the input, so the transcript keeps the whole width.
extension Sidebar {
    /// The band's least height: the input's most rows (the owner's choice: always six).
    static let bandRows = 6
    /// Under this the full layout keeps the screen: six rows of band would take most of it.
    static let bandScreenRows = 18
    /// Where the full sidebar would leave the transcript fewer columns than this, `adaptive` takes the band.
    static let adaptiveColumns = 100

    /// The panel's width for a screen `columns` wide, not counting the divider.
    static func width(for columns: Int) -> Int { Swift.min(36, Swift.max(22, columns / 4)) }

    /// The open sidebar sized for the band, when the layout puts it there on this screen; nil when it is beside the transcript, or
    /// closed. Six rows, more when it needs them, at most a third of the screen.
    static func band(_ state: ScreenState, columns: Int, screenRows: Int) -> Sidebar? {
        guard isShown(state, columns: columns), screenRows >= bandScreenRows else { return nil }
        switch state.sidebarLayout {
            case .full: return nil
            case .bottom: break
            case .adaptive where columns - width(for: columns) - 1 >= adaptiveColumns: return nil
            case .adaptive: break
        }
        // The toggle and the entries; the counts are the status line's, at its trailing edge.
        let needed = SidebarEntries(state, columns: width(for: columns) - 1).entries.count + 1
        return Sidebar(
            state,
            columns: columns,
            rows: Swift.max(bandRows, Swift.min(needed, screenRows / 3)),
            counts: false
        )
    }

    /// The columns the transcript wraps to on a screen `columns` by `screenRows`: less the panel and its divider when the sidebar is
    /// beside it, all of them when it is closed or in the band.
    static func transcriptColumns(_ state: ScreenState, columns: Int, screenRows: Int) -> Int {
        guard isShown(state, columns: columns), band(state, columns: columns, screenRows: screenRows) == nil else {
            return columns
        }
        return columns - width(for: columns) - 1
    }
}
