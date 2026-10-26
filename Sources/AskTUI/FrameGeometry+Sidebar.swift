extension FrameGeometry {
    /// Records the sidebar's share of the width: where the transcript ends, and the runner each row of the panel shows.
    mutating func placeSidebar(_ sidebar: Sidebar, columns: Int) {
        transcriptColumns = sidebar.transcriptColumns(of: columns)
        sidebarIDs = sidebar.ids
    }
}
