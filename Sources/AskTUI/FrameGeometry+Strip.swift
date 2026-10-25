extension FrameGeometry {
    /// The geometry with the strip's rows: where the first was drawn, and the runner each shows.
    func withStrip(_ strip: RunnerStrip, firstRow: Int) -> FrameGeometry {
        var geometry = self
        geometry.stripFirstRow = firstRow
        geometry.stripIDs = strip.ids
        return geometry
    }
}
