internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A drag in the input selects the draft's text: it highlights, the cursor follows, it copies, and typing replaces it.
@Suite("A drag in the input selects text there")
struct InputSelectionTests {
    /// Thirty columns on twelve rows. The input is the last row, and its first five cells are the `ask> ` prefix.
    private func rig(_ draft: String, options: ScreenOptions = ScreenOptions()) -> PointerRig {
        var rig = PointerRig(options: options, lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    private func type(_ text: String, into rig: inout PointerRig) {
        for character in text {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(character.asciiValue!))), pageRows: 10)
        }
        rig.draw()
    }

    private func key(_ code: UInt32, into rig: inout PointerRig, modifiers: KeyModifiers = []) {
        _ = rig.controller.handle(.key(KeyEvent(keyCode: code, modifiers: modifiers)), pageRows: 10, columns: 30)
        rig.draw()
    }

    @Test func `a drag selects from the press to the pointer, both characters included, and copies on release`() {
        var rig = rig("hello world")
        let effects = rig.drag(from: (11, 6), to: (11, 9))
        #expect(effects == [.copy("ello")])
        #expect(rig.inverse(row: 11) == [6, 7, 8, 9])
        #expect(rig.controller.state.inputSelection == 1 ..< 5)
        #expect(rig.controller.state.editor.cursor == 5, "the cursor is at the end being dragged")
    }

    @Test func `a drag backwards selects the same characters and leaves the cursor at the start`() {
        var rig = rig("hello world")
        let effects = rig.drag(from: (11, 9), to: (11, 6))
        #expect(effects == [.copy("ello")])
        #expect(rig.controller.state.editor.cursor == 1)
    }

    @Test func `a drag past the end of the text takes the rest and not a character that is not there`() {
        var rig = rig("hello world")
        let effects1 = rig.drag(from: (11, 6), to: (11, 29))
        #expect(effects1 == [.copy("ello world")])
        var prefix = self.rig("hello")
        let effects2 = prefix.drag(from: (11, 3), to: (11, 7))
        #expect(effects2 == [.copy("hel")], "the prefix is not text")
    }

    @Test func `a drag across lines takes the line break and highlights each line's part`() {
        var rig = rig("ab\ncd\nef")
        let effects3 = rig.drag(from: (9, 6), to: (10, 0))
        #expect(effects3 == [.copy("b\nc")])
        #expect(rig.inverse(row: 9) == [6])
        #expect(rig.inverse(row: 10) == [0])
        #expect(rig.inverse(row: 11).isEmpty)
    }

    @Test func `a wide character is selected whole`() {
        var rig = rig("日本語")
        let effects4 = rig.drag(from: (11, 5), to: (11, 7))
        #expect(effects4 == [.copy("日本")])
        #expect(rig.inverse(row: 11) == [5, 6, 7, 8])
    }

    @Test func `a drag that leaves the pressed cell and comes back selects that one character`() {
        var rig = rig("hello world")
        rig.mouse(.left, .press, row: 11, col: 7)
        rig.mouse(.left, .drag, row: 11, col: 10)
        rig.mouse(.left, .drag, row: 11, col: 7)
        let effects = rig.mouse(.left, .release, row: 11, col: 7)
        #expect(effects == [.copy("l")])
    }

    @Test func `the highlight of each drawn row is exact, and a line break adds nothing`() {
        var editor = PromptEditor()
        editor.paste("ab\ncd\nef")
        var layout = PromptLayout()
        let frame = layout.frame(editor, columns: 30, screenRows: 12, maximumRows: 6, selection: 1 ..< 4)
        #expect(frame.highlights == [6 ..< 7, 0 ..< 1, nil])
        let wide = layout.frame(editor, columns: 30, screenRows: 12, maximumRows: 6, selection: 0 ..< 8)
        #expect(wide.highlights == [5 ..< 7, 0 ..< 2, 0 ..< 2])
        #expect(layout.frame(editor, columns: 30, screenRows: 12, maximumRows: 6).highlights.isEmpty)
    }

    @Test func `typing replaces what is selected, and a paste does too`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (11, 6), to: (11, 9))
        type("X", into: &rig)
        #expect(rig.controller.state.editor.text == "hX world")
        #expect(rig.controller.state.inputSelection == nil)
        _ = rig.drag(from: (11, 5), to: (11, 6))
        _ = rig.controller.handle(.paste("YY"), pageRows: 10)
        #expect(rig.controller.state.editor.text == "YY world")
    }

    @Test func `backspace deletes what is selected and only that`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (11, 6), to: (11, 9))
        key(0x7F, into: &rig)
        #expect(rig.controller.state.editor.text == "h world")
        #expect(rig.controller.state.editor.cursor == 1)
    }

    @Test func `a cursor key drops the selection and edits nothing`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (11, 6), to: (11, 9))
        key(Key.left.rawValue, into: &rig)
        #expect(rig.controller.state.editor.text == "hello world")
        #expect(rig.controller.state.inputSelection == nil)
        #expect(rig.inverse(row: 11).isEmpty)
    }

    @Test func `with copy on select off, control C copies and consumes it, and escape just clears`() {
        var rig = PointerRig(columns: 100, options: ScreenOptions(copyOnSelect: false), lines: ["one", "two"])
        _ = rig.controller.handle(.paste("hello world"), pageRows: 10)
        rig.draw()
        let effects5 = rig.drag(from: (11, 6), to: (11, 9))
        #expect(effects5.isEmpty)
        #expect(rig.text(row: 10).contains("ctrl+c copy · esc clear"))
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        #expect(effects == [.copy("ello")])
        #expect(rig.controller.state.inputSelection == nil)
        _ = rig.drag(from: (11, 6), to: (11, 9))
        #expect(rig.controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 10).isEmpty)
        #expect(rig.controller.state.inputSelection == nil && rig.controller.state.editor.text == "hello world")
    }

    @Test func `a click drops the selection and places the cursor`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (11, 6), to: (11, 9))
        rig.click(row: 11, col: 12)
        #expect(rig.controller.state.inputSelection == nil)
        #expect(rig.controller.state.editor.cursor == 7)
    }

    @Test func `with the mouse off, or a question waiting, a drag selects nothing`() {
        var off = rig("hello", options: ScreenOptions(mouse: false))
        let effects6 = off.drag(from: (11, 6), to: (11, 9))
        #expect(effects6.isEmpty && off.controller.state.inputSelection == nil)
        var asking = rig("hello")
        asking.controller.handle(.askApproval(id: 1, question: "Run it?"))
        asking.draw()
        _ = asking.drag(from: (11, 6), to: (11, 9))
        #expect(asking.controller.state.inputSelection == nil)
    }

    @Test func `a selection in the transcript is dropped when one starts in the input`() {
        var rig = rig("hello")
        _ = rig.drag(from: (9, 0), to: (9, 2))
        #expect(rig.controller.state.selection != nil)
        _ = rig.drag(from: (11, 6), to: (11, 8))
        #expect(rig.controller.state.selection == nil && rig.controller.state.inputSelection != nil)
    }

    @Test func `a drag held at the top row of a tall draft steps up a row a tick, and the window follows`() {
        var rig = rig((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        let rows = rig.composer.transcriptRows
        let first = rows + 1
        rig.mouse(.left, .press, row: 11, col: 2)
        rig.mouse(.left, .drag, row: first, col: 2)
        #expect(rig.controller.isAutoscrolling)
        var ticks = 0
        while rig.tick() { ticks += 1 }
        #expect(ticks >= 5)
        #expect(!rig.controller.isAutoscrolling)
        #expect(rig.text(row: first).hasSuffix("line 1") || rig.text(row: first).contains("line 1"))
        let effects = rig.mouse(.left, .release, row: first, col: 2)
        guard case .copy(let text) = effects.first else {
            Issue.record("nothing was copied")
            return
        }
        #expect(text.hasPrefix("line 1\nline 2") && text.hasSuffix("line 9\nlin"))
    }

    @Test func `releasing the button stops the timer`() {
        var rig = rig((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        let first = rig.composer.transcriptRows + 1
        rig.mouse(.left, .press, row: 11, col: 2)
        rig.mouse(.left, .drag, row: first, col: 2)
        rig.mouse(.left, .release, row: first, col: 2)
        #expect(!rig.controller.isAutoscrolling)
        let ticked = rig.tick()
        #expect(!ticked)
    }
}
