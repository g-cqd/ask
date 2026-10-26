internal import TerminalKitRender
internal import Testing

@testable import AskTUI

@Suite("A tiny or empty terminal never gives the input an invalid cell")
struct PromptViewportBoundaryTests {
    @Test(arguments: [(0, 0), (0, 5), (5, 0)])
    func `an empty dimension produces no transcript and a neutral cursor`(columns: Int, rows: Int) {
        var state = ScreenState(label: "m", options: .legacy)
        state.editor.paste("日本\ntext")
        var buffer = ScreenBuffer(columns: columns, rows: rows)
        var composer = ScreenComposer()
        let cursor = composer.compose(state, into: &buffer)
        #expect(cursor.row == 0 && cursor.column == 0)
        #expect(composer.transcriptRows == 0)
    }

    @Test func `one row leaves room for the cursor rather than drawing a status outside the buffer`() {
        for columns in [1, 2, 5, 8] {
            for rows in 1 ... 3 {
                var state = ScreenState(label: "m", options: .legacy)
                state.promptRows = Int.min
                state.editor.paste("日本\ntext")
                var buffer = ScreenBuffer(columns: columns, rows: rows)
                var composer = ScreenComposer()
                let cursor = composer.compose(state, into: &buffer)
                #expect((0 ..< rows).contains(cursor.row))
                #expect((0 ..< columns).contains(cursor.column))
            }
        }
    }
}
