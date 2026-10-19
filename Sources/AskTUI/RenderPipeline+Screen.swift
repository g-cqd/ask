public import TerminalKitRender

extension RenderPipeline {
    /// Draws one frame of `state`: lays it out with `composer`, places the cursor in the prompt, and flushes,
    /// or redraws everything when `full`.
    ///
    /// The transcript's rows are the pipeline's scroll region, so a streamed line moves the terminal's rows
    /// instead of rewriting them (TerminalKit ADR-0022). The region follows the transcript as the prompt grows
    /// and shrinks.
    public func draw(_ state: ScreenState, with composer: inout ScreenComposer, full: Bool = false) throws {
        beginFrame()
        let cursor = composer.compose(state, into: &buffer)
        (cursorRow, cursorCol) = (cursor.row, cursor.column)
        scrollRegion = 0 ..< composer.transcriptRows
        if full { try forceRedraw() } else { try flush() }
    }
}
