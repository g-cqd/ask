public import TerminalKitRender

/// The screen as a TerminalKit render loop draws it: on the loop's thread, one frame per state it takes.
///
/// The transcript's rows are the pipeline's scroll region, so a streamed line moves the terminal's rows instead of
/// rewriting them (TerminalKit ADR-0022). The region follows the transcript as the prompt grows and shrinks.
extension ScreenComposer: FrameComposer {
    public mutating func compose(_ state: ScreenState, into pipeline: RenderPipeline) {
        let cursor = compose(state, into: &pipeline.buffer)
        // A cursor that is not on screen is hidden, not drawn somewhere it is not.
        (pipeline.cursorRow, pipeline.cursorCol) = cursorIsVisible ? (cursor.row, cursor.column) : (nil, nil)
        pipeline.scrollRegion = 0 ..< transcriptRows
    }
}
