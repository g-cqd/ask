internal import TerminalKitIO
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// The transcript is a scroll region (TerminalKit roadmap 0011): a line streamed into a full transcript moves
/// the terminal's rows with DECSTBM and SU, and only the new line is drawn.
@Suite("A streamed line scrolls the transcript")
struct StreamingScreenTests {
    @Test func `a line streamed into a full transcript is a scroll, not a redraw`() throws {
        let connection = MockTerminalConnection()  // 80x24: 22 transcript rows, a status row, a prompt row
        let pipeline = RenderPipeline(connection: connection, columns: 80, rows: 24)
        var composer = ScreenComposer()
        var state = ScreenState(label: "m")
        for index in 0 ..< 40 { state.transcript.addNotice("earlier line \(index) of a long answer", isError: false) }
        pipeline.beginFrame()
        composer.compose(state, into: pipeline)
        try pipeline.forceRedraw()

        state.transcript.addNotice("the streamed line", isError: false)
        connection.clearOutput()
        pipeline.beginFrame()
        composer.compose(state, into: pipeline)
        try pipeline.flush()

        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(output.contains("\u{1B}[1;22r\u{1B}[1S"))
        #expect(!output.contains("earlier line 30"), "a line that only moved was redrawn")
    }

    @Test func `a taller prompt shrinks the region with the transcript`() throws {
        let pipeline = RenderPipeline(connection: MockTerminalConnection(), columns: 80, rows: 24)
        var composer = ScreenComposer()
        var state = ScreenState(label: "m")
        state.editor.paste(String(repeating: "x", count: 200))  // three prompt rows at 80 columns

        pipeline.beginFrame()
        composer.compose(state, into: pipeline)

        #expect(pipeline.scrollRegion == 0 ..< 20)
    }
}
