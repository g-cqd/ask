internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

@Suite("Text and spacing provide hierarchy without leading glyphs or painted surfaces")
struct ContentStyleTests {
    @Test func `a user block begins with its text and uses bold rather than a leading marker`() {
        let rig = PointerRig(updates: [.userPrompt("hello")])
        #expect(rig.text(row: 9) == "hello")
        #expect(rig.buffer[9, 0].style.bold)
    }

    @Test func `fold placeholders identify their contents in text without disclosure glyphs`() {
        let rig = PointerRig(
            columns: 80,
            updates: [
                .thinkingText("one\ntwo"), .toolStarted(name: "read", summary: "file"),
                .toolFinished(.succeeded, output: "result")
            ])
        #expect(rig.text(row: 8) == "thinking · 2 lines")
        #expect(rig.text(row: 9) == "read file ✓ · 1 line")
    }

    @Test func `the status line and transcript keep the terminal's default background`() {
        let rig = PointerRig(updates: [.userPrompt("hello"), .assistantText("answer")])
        for row in 0 ..< rig.buffer.rows {
            for col in 0 ..< rig.buffer.columns {
                let style = rig.buffer[row, col].style
                #expect(style.bg == .default && !style.inverse, "painted cell at \(row),\(col)")
            }
        }
    }

    @Test func `selection alone reverses the selected cells, never the status surface`() {
        var rig = PointerRig(lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        for row in 0 ..< rig.buffer.rows {
            let expected = row == 9 ? [0, 1, 2, 3, 4] : []
            #expect(rig.inverse(row: row) == expected)
        }
    }
}
