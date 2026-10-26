internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// Ctrl-X cuts what is selected in the input; with nothing selected it still clears the draft (ADR-0059).
@Suite("Control X cuts a selection in the input")
struct InputCutTests {
    private static let cutKeys = [KeyEvent(keyCode: 0x18), KeyEvent(keyCode: 0x78, modifiers: .ctrl)]

    /// A hundred columns, so the status line is not clipped. The input is the last row; its first five cells are the prefix.
    private func rig(
        _ draft: String,
        options: ScreenOptions = ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false)
    ) -> PointerRig {
        var rig = PointerRig(columns: 100, options: options, lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    private func select(_ rig: inout PointerRig, from: Int, to: Int) {
        _ = rig.drag(from: (10, 5 + from), to: (10, 5 + to))
    }

    @Test(arguments: cutKeys)
    func `a cut removes the selection, puts it on the clipboard, and leaves the cursor where it was`(key: KeyEvent) {
        var rig = rig("hello world")
        select(&rig, from: 1, to: 4)
        let effects = rig.controller.handle(.key(key), pageRows: 10)
        #expect(effects == [.copy("ello")])
        #expect(rig.controller.state.editor.text == "h world")
        #expect(rig.controller.state.editor.cursor == 1)
        #expect(rig.controller.state.inputSelection == nil)
    }

    @Test func `it cuts even when copy on select is off, which only governs what a selection does by itself`() {
        var rig = rig(
            "hello world",
            options: ScreenOptions(copyOnSelect: false, prompt: "ask> ", tint: false, separator: false, padding: false))
        select(&rig, from: 6, to: 10)
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10)
        #expect(effects == [.copy("world")])
        #expect(rig.controller.state.editor.text == "hello ")
    }

    @Test func `it cuts a selection made from the keyboard and one made by a double click`() {
        var shifted = rig("hello world")
        shifted.controller.state.editor.place(cursor: 0)
        shifted.draw()
        for _ in 0 ..< 5 {
            _ = shifted.controller.handle(.key(KeyEvent(keyCode: Key.right.rawValue, modifiers: .shift)), pageRows: 10)
        }
        #expect(shifted.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10) == [.copy("hello")])
        #expect(shifted.controller.state.editor.text == " world")
        var double = self.rig("hello world")
        double.mouse(.left, .press, row: 10, col: 7, after: .seconds(1))
        double.mouse(.left, .release, row: 10, col: 7)
        double.mouse(.left, .press, row: 10, col: 7, after: .milliseconds(50))
        double.mouse(.left, .release, row: 10, col: 7)
        #expect(double.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10) == [.copy("hello")])
        #expect(double.controller.state.editor.text == " world")
    }

    @Test func `cutting everything leaves an empty draft`() {
        var rig = rig("ab\ncd")
        _ = rig.drag(from: (9, 5), to: (10, 6))
        #expect(rig.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10) == [.copy("ab\ncd")])
        #expect(rig.controller.state.editor.text.isEmpty && rig.controller.state.editor.cursor == 0)
    }

    @Test func `with nothing selected control X still clears the whole draft and copies nothing`() {
        var rig = rig("first\nsecond")
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10)
        #expect(effects.isEmpty)
        #expect(rig.controller.state.editor.text.isEmpty)
    }

    @Test func `a selection in the transcript is not cut, and the draft is cleared as before`() {
        var rig = rig("draft")
        _ = rig.drag(from: (8, 0), to: (8, 2))
        #expect(rig.controller.state.selection != nil)
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10)
        #expect(effects.isEmpty)
        #expect(rig.controller.state.editor.text.isEmpty)
    }

    @Test func `the status line offers the cut for a selection in the input only`() {
        var input = rig("hello world")
        select(&input, from: 1, to: 4)
        #expect(input.text(row: 11).contains("ctrl+c copy · esc clear · ctrl+x cut"))
        var transcript = self.rig("hello world")
        _ = transcript.drag(from: (8, 0), to: (8, 2))
        #expect(transcript.text(row: 11).contains("ctrl+c copy"))
        #expect(!transcript.text(row: 11).contains("ctrl+x"))
    }

    @Test func `a waiting question keeps the keys`() {
        var rig = rig("hello")
        select(&rig, from: 1, to: 3)
        rig.controller.handle(.askApproval(id: 1, question: "Run it?"))
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x18)), pageRows: 10)
        #expect(effects.isEmpty)
        #expect(rig.controller.state.editor.text == "hello")
    }
}
