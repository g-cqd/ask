internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

@Suite("The input has a configurable bounded display-row viewport")
struct BoundedPromptTests {
    @Test func `the requested limit bounds the input without truncating its text`() {
        var rig = PointerRig(columns: 60, rows: 30)
        let text = (1 ... 10).map { "line \($0)" }.joined(separator: "\n")
        rig.controller.state.promptRows = 2
        rig.controller.state.editor.paste(text)
        rig.draw()
        #expect(rig.composer.transcriptRows == 27)
        #expect([27, 28].map { rig.text(row: $0) } == ["line 9", "line 10"])
        #expect(rig.controller.state.editor.text == text)
        #expect(rig.cursor.row == 28)
    }

    @Test func `a large setting cannot take more than a third of the terminal`() {
        var rig = PointerRig(columns: 60, rows: 12)
        rig.controller.state.promptRows = 99
        rig.controller.state.editor.paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        rig.draw()
        #expect(rig.composer.transcriptRows == 7)
        #expect((7 ..< 11).map { rig.text(row: $0) } == (7 ... 10).map { "line \($0)" })
    }

    @Test func `the cursor before a soft-wrapped character is on its new row, never one column past the edge`() {
        var rig = PointerRig(columns: 8, rows: 12)
        rig.controller.state.editor.paste("abcd")
        _ = rig.controller.state.editor.apply(KeyEvent(keyCode: Key.left.rawValue))
        rig.draw()
        #expect(rig.text(row: 9) == "ask> abc" && rig.text(row: 10) == "d")
        #expect(rig.cursor.row == 10 && rig.cursor.column == 0)
    }

    @Test func `clipping is described in the existing status row, not another input row`() {
        var rig = PointerRig(columns: 80, rows: 12)
        rig.controller.state.promptRows = 3
        rig.controller.state.editor.paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        rig.draw()
        #expect(rig.text(row: 11).contains("input 8–10 of 10"))
        #expect(rig.composer.transcriptRows == 8)
    }

    @Test func `a narrow status prioritises the input clipping cue over the model label`() {
        var rig = PointerRig(columns: 20, rows: 12)
        rig.controller.state.label = "a-long-model-label"
        rig.controller.state.promptRows = 2
        rig.controller.state.editor.paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        rig.draw()
        #expect(rig.text(row: 11).hasPrefix("input 9–10 of 10"))
    }

    @Test func `resizing keeps the source text and a cursor cell inside the viewport`() {
        var rig = PointerRig(columns: 20, rows: 12)
        rig.controller.state.editor.paste("a日本 e\u{301} text that wraps on a small terminal")
        _ = rig.controller.state.editor.apply(KeyEvent(keyCode: Key.home.rawValue))
        for columns in [8, 3, 12] {
            rig.buffer = ScreenBuffer(columns: columns, rows: 9)
            rig.draw()
            #expect((0 ..< 9).contains(rig.cursor.row))
            #expect((0 ..< columns).contains(rig.cursor.column))
        }
        #expect(rig.controller.state.editor.text == "a日本 e\u{301} text that wraps on a small terminal")
    }
}
