internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A double click in the input takes a word, a triple click the line, by the rules the transcript uses.
@Suite("A double or triple click in the input selects a word or a line")
struct InputWordSelectionTests {
    /// Thirty columns on twelve rows. The input is the last row, and its first five cells are the `ask> ` prefix.
    private func rig(_ draft: String, options: ScreenOptions = ScreenOptions()) -> PointerRig {
        var rig = PointerRig(options: options, lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    private func double(_ rig: inout PointerRig, row: Int = 11, col: Int) -> [ScreenController.Effect] {
        rig.mouse(.left, .press, row: row, col: col, after: .seconds(1))
        rig.mouse(.left, .release, row: row, col: col)
        rig.mouse(.left, .press, row: row, col: col, after: .milliseconds(50))
        return rig.mouse(.left, .release, row: row, col: col)
    }

    private func triple(_ rig: inout PointerRig, row: Int, col: Int) -> [ScreenController.Effect] {
        _ = double(&rig, row: row, col: col)
        rig.mouse(.left, .press, row: row, col: col, after: .milliseconds(50))
        return rig.mouse(.left, .release, row: row, col: col)
    }

    @Test func `a double click takes the word, highlights it, puts the cursor after it and copies it`() {
        var rig = rig("hello world")
        let effects = double(&rig, col: 6)
        #expect(effects == [.copy("hello")])
        #expect(rig.controller.state.inputSelection == 0 ..< 5)
        #expect(rig.controller.state.editor.cursor == 5)
        #expect(rig.inverse(row: 11) == [5, 6, 7, 8, 9])
    }

    @Test
    func
        `the run under the pointer is the one taken: spaces together, punctuation together, a word with its underscores`()
    {
        var spaces = rig("a   b")
        #expect(double(&spaces, col: 7) == [.copy("   ")])
        var punctuation = rig("x...y")
        #expect(double(&punctuation, col: 7) == [.copy("...")])
        var snake = rig("my_var1 = 2")
        #expect(double(&snake, col: 8) == [.copy("my_var1")])
    }

    @Test func `past the end of the line the last run is taken, as in the transcript`() {
        var rig = rig("hello world")
        #expect(double(&rig, col: 28) == [.copy("world")])
    }

    @Test func `a wide word is taken whole, and a tab does not shift what is taken`() {
        var wide = rig("日本語 abc")
        #expect(double(&wide, col: 7) == [.copy("日本語")])
        var tab = rig("a\tbc")
        #expect(double(&tab, col: 5 + 4 + 1) == [.copy("bc")])
    }

    @Test func `a triple click takes the hard line, not its line break, the other lines, or just the word`() {
        var rig = rig("ab\ncd ef\ngh")
        let effects = triple(&rig, row: 10, col: 1)
        #expect(effects == [.copy("cd ef")])
        #expect(rig.controller.state.inputSelection == 3 ..< 8)
        #expect(rig.inverse(row: 10) == [0, 1, 2, 3, 4])
        #expect(rig.inverse(row: 9).isEmpty && rig.inverse(row: 11).isEmpty)
    }

    @Test func `a double click on another line takes that line's word`() {
        var rig = rig("ab cd\nef gh")
        #expect(double(&rig, row: 11, col: 4) == [.copy("gh")])
        #expect(rig.controller.state.inputSelection == 9 ..< 11)
    }

    @Test func `an empty line has nothing to take`() {
        var rig = rig("ab\n\ncd")
        #expect(double(&rig, row: 10, col: 0).isEmpty)
        #expect(rig.controller.state.inputSelection == nil)
    }

    @Test func `typing replaces the double-clicked word, and a click elsewhere drops it`() {
        var rig = rig("hello world")
        _ = double(&rig, col: 6)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("X").asciiValue!))), pageRows: 10)
        #expect(rig.controller.state.editor.text == "X world")
        var again = self.rig("hello world")
        _ = double(&again, col: 6)
        again.click(row: 11, col: 14)
        #expect(again.controller.state.inputSelection == nil)
    }

    @Test func `with copy on select off the word is kept without copying, and control C copies it`() {
        var rig = rig("hello world", options: ScreenOptions(copyOnSelect: false))
        #expect(double(&rig, col: 6).isEmpty)
        #expect(rig.controller.state.inputSelection == 0 ..< 5)
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        #expect(effects == [.copy("hello")])
    }

    @Test func `with the mouse off, or a question waiting, nothing is taken`() {
        var off = rig("hello", options: ScreenOptions(mouse: false))
        #expect(double(&off, col: 6).isEmpty && off.controller.state.inputSelection == nil)
        var asking = rig("hello")
        asking.controller.handle(.askApproval(id: 1, question: "Run it?"))
        asking.draw()
        _ = double(&asking, col: 6)
        #expect(asking.controller.state.inputSelection == nil)
    }
}
