extension FrameGeometry {
    /// Records the sidebar's place: where the transcript ends, the divider's column, the row the panel starts on, and the runner each
    /// of its rows shows. In the bottom band (`inBand`) the transcript keeps the whole width.
    mutating func placeSidebar(_ sidebar: Sidebar, columns: Int, top: Int = 0, inBand: Bool = false) {
        transcriptColumns = inBand ? columns : sidebar.transcriptColumns(of: columns)
        sidebarColumn = columns - sidebar.width - 1
        sidebarTop = top
        sidebarIDs = sidebar.ids
        sidebarCorner = sidebar.cornerColumn
    }
}
