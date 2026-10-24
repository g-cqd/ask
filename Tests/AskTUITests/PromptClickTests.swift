internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A click in the input puts the cursor on the character under it, by the map the input was drawn with.
@Suite("A click in the input places the cursor")
struct PromptClickTests {
    /// Thirty columns on twelve rows: the input is the last row, and its first five cells are the `ask> ` prefix.
    private func rig(options: ScreenOptions = ScreenOptions()) -> PointerRig {
        PointerRig(options: options, lines: ["one", "two"])
    }

    private func paste(_ text: String, into rig: inout PointerRig) {
        _ = rig.controller.handle(.paste(text), pageRows: 10)
        rig.draw()
    }

    private func place(_ rig: inout PointerRig, row: Int, col: Int) -> Int {
        rig.click(row: row, col: col)
        return rig.controller.state.editor.cursor
    }

    @Test func `a click puts the cursor before the character under it`() {
        var rig = rig()
        paste("hello world", into: &rig)
        #expect(place(&rig, row: 11, col: 7) == 2)
        #expect(place(&rig, row: 11, col: 5) == 0)
        #expect(place(&rig, row: 11, col: 15) == 10)
    }

    @Test func `the prefix and the space past the end are clicks on the nearest caret`() {
        var rig = rig()
        paste("hello", into: &rig)
        #expect(place(&rig, row: 11, col: 0) == 0)
        #expect(place(&rig, row: 11, col: 29) == 5)
    }

    @Test func `a click on another line of the draft goes to that line`() {
        var rig = rig()
        paste("ab\ncd\nef", into: &rig)
        #expect(place(&rig, row: 10, col: 1) == 4)
        #expect(place(&rig, row: 9, col: 0) == 0)
        #expect(place(&rig, row: 11, col: 1) == 7)
    }

    @Test func `a wrapped line is clicked by the row it wraps onto`() {
        var rig = rig()
        paste(String(repeating: "x", count: 20) + String(repeating: "y", count: 20), into: &rig)
        // Twenty-five cells fit on the first row, after the prefix; the rest wraps.
        #expect(rig.controller.state.editor.text.count == 40)
        #expect(place(&rig, row: rig.composer.transcriptRows + 2, col: 3) == 28)
    }

    @Test func `a tall draft clicks the rows that are drawn, not the first ones`() {
        var rig = rig()
        paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n"), into: &rig)
        // Four input rows on twelve: the draft shows its last rows, 8 to 10, and the top of the window is not the top of the draft.
        let top = rig.composer.transcriptRows + 1
        let lines = rig.controller.state.editor.text.split(separator: "\n", omittingEmptySubsequences: false)
        let firstDrawn = (0 ..< lines.count).first { rig.text(row: top).hasSuffix(String(lines[$0])) } ?? -1
        #expect(firstDrawn > 0, "the window is scrolled: its first row is not the first line")
        rig.click(row: top, col: 1)
        let start = lines[..<firstDrawn].reduce(0) { $0 + $1.count + 1 }
        #expect(rig.controller.state.editor.cursor == start + 1)
    }

    @Test func `a wide character is clicked whole`() {
        var rig = rig()
        paste("日本語", into: &rig)
        #expect(place(&rig, row: 11, col: 5) == 0)
        #expect(place(&rig, row: 11, col: 6) == 0, "the second cell of a wide character is the character")
        #expect(place(&rig, row: 11, col: 7) == 1)
    }

    @Test func `typing after a click inserts there, and a vertical move starts from there`() {
        var rig = rig()
        paste("hello\nworld", into: &rig)
        _ = place(&rig, row: 10, col: 7)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("X").asciiValue!))), pageRows: 10)
        #expect(rig.controller.state.editor.text == "heXllo\nworld")
        _ = rig.controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: 10, columns: 30)
        #expect(
            rig.controller.state.editor.cursor == 12,
            "the wanted column, 8 cells in, is past the end of the shorter second line")
    }

    @Test func `a click forgets the column an earlier Up or Down was aiming for`() {
        var rig = rig()
        paste("abcd\nefghij", into: &rig)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: Key.up.rawValue)), pageRows: 10, columns: 30)
        #expect(rig.controller.state.editor.cursor == 1, "six cells in on the first line, after its five-cell prefix")
        #expect(place(&rig, row: 10, col: 5) == 0)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: 10, columns: 30)
        #expect(rig.controller.state.editor.cursor == 10, "from the clicked cell, not from the old aim")
    }

    @Test func `a click in the input drops the selection in the transcript`() {
        var rig = rig()
        paste("draft", into: &rig)
        rig.drag(from: (9, 0), to: (9, 2))
        #expect(rig.controller.state.selection != nil)
        rig.click(row: 11, col: 7)
        #expect(rig.controller.state.selection == nil)
    }

    @Test func `with the mouse off, or a question waiting, a click leaves the cursor`() {
        var off = rig(options: ScreenOptions(mouse: false))
        paste("hello", into: &off)
        #expect(place(&off, row: 11, col: 6) == 5)
        var asking = rig()
        paste("hello", into: &asking)
        asking.controller.handle(.askApproval(id: 1, question: "Run it?"))
        asking.draw()
        #expect(place(&asking, row: 11, col: 6) == 5)
    }

    @Test func `a click above the input does not place the cursor`() {
        var rig = rig()
        paste("hello", into: &rig)
        #expect(place(&rig, row: 3, col: 6) == 5)
        #expect(place(&rig, row: 10, col: 6) == 5, "the status line is not the input")
    }
}
