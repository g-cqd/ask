extension FrameGeometry {
    /// Records the strip's rows: where the first was drawn, and the runner each shows.
    mutating func placeStrip(_ strip: RunnerStrip, firstRow: Int) {
        stripFirstRow = firstRow
        stripIDs = strip.ids
    }
}
