internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// Shift with an arrow, Home or End selects text in the input from the keyboard.
@Suite("Shift and a cursor key select text in the input")
struct InputKeyboardSelectionTests {
    /// Thirty columns on twelve rows. The input is the last row, and its first five cells are the `ask> ` prefix.
    private func rig(_ draft: String) -> PointerRig {
        var rig = PointerRig(lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    @discardableResult
    private func press(
        _ rig: inout PointerRig, _ code: UInt32, shift: Bool = true, control: Bool = false
    ) -> [ScreenController.Effect] {
        var modifiers: KeyModifiers = shift ? [.shift] : []
        if control { modifiers.insert(.ctrl) }
        let effects = rig.controller.handle(
            .key(KeyEvent(keyCode: code, modifiers: modifiers)), pageRows: 10, columns: 30)
        rig.draw()
        return effects
    }

    private func home(_ rig: inout PointerRig) {
        rig.controller.state.editor.place(cursor: 0)
        rig.draw()
    }

    @Test func `shift and right extend from the cursor, and the cursor goes with the end`() {
        var rig = rig("hello world")
        home(&rig)
        for _ in 0 ..< 3 { press(&rig, Key.right.rawValue) }
        #expect(rig.controller.state.inputSelection == 0 ..< 3)
        #expect(rig.controller.state.editor.cursor == 3)
        #expect(rig.inverse(row: 11) == [5, 6, 7])
    }

    @Test func `shift and left from the end take the last characters`() {
        var rig = rig("hello")
        press(&rig, Key.left.rawValue)
        press(&rig, Key.left.rawValue)
        #expect(rig.controller.state.inputSelection == 3 ..< 5)
    }

    @Test func `going back to where it began leaves nothing selected, and crossing it flips the selection`() {
        var rig = rig("hello world")
        rig.controller.state.editor.place(cursor: 5)
        rig.draw()
        press(&rig, Key.left.rawValue)
        press(&rig, Key.left.rawValue)
        #expect(rig.controller.state.inputSelection == 3 ..< 5)
        press(&rig, Key.right.rawValue)
        press(&rig, Key.right.rawValue)
        #expect(rig.controller.state.inputSelection == nil)
        press(&rig, Key.right.rawValue)
        press(&rig, Key.right.rawValue)
        #expect(rig.controller.state.inputSelection == 5 ..< 7)
    }

    @Test func `shift with home and end reaches the ends of the hard line`() {
        var rig = rig("ab cd\nef gh")
        rig.controller.state.editor.place(cursor: 9)
        rig.draw()
        press(&rig, Key.home.rawValue)
        #expect(rig.controller.state.inputSelection == 6 ..< 9)
        rig.controller.clearSelection()
        rig.controller.state.editor.place(cursor: 7)
        rig.draw()
        press(&rig, Key.end.rawValue)
        #expect(rig.controller.state.inputSelection == 7 ..< 11)
    }

    @Test func `shift with up and down extends by the display rows the input is drawn with`() {
        var rig = rig(String(repeating: "x", count: 20) + String(repeating: "y", count: 20))
        // Twenty-five cells fit on the first row after the prefix, so the end of the draft is on the second.
        let before = rig.controller.state.editor.cursor
        press(&rig, Key.up.rawValue)
        let range = rig.controller.state.inputSelection
        #expect(range != nil && range!.upperBound == before && range!.count > 10)
        press(&rig, Key.down.rawValue)
        #expect(rig.controller.state.inputSelection == nil)
    }

    @Test func `typing replaces it, backspace deletes it, and a plain cursor key drops it`() {
        var typing = rig("hello world")
        home(&typing)
        for _ in 0 ..< 5 { press(&typing, Key.right.rawValue) }
        _ = typing.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("X").asciiValue!))), pageRows: 10)
        #expect(typing.controller.state.editor.text == "X world")
        var deleting = self.rig("hello world")
        home(&deleting)
        for _ in 0 ..< 5 { press(&deleting, Key.right.rawValue) }
        _ = deleting.controller.handle(.key(KeyEvent(keyCode: 0x7F)), pageRows: 10)
        #expect(deleting.controller.state.editor.text == " world")
        var plain = self.rig("hello world")
        home(&plain)
        press(&plain, Key.right.rawValue)
        press(&plain, Key.right.rawValue, shift: false)
        #expect(plain.controller.state.inputSelection == nil && plain.controller.state.editor.text == "hello world")
        press(&plain, Key.right.rawValue)
        #expect(plain.controller.state.inputSelection == 2 ..< 3, "a new selection begins where the cursor now is")
    }

    @Test func `control C copies it and consumes it, and escape clears it`() {
        var rig = rig("hello world")
        home(&rig)
        for _ in 0 ..< 5 { press(&rig, Key.right.rawValue) }
        #expect(rig.text(row: 10).contains("ctrl+c"))
        let effects = rig.controller.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        #expect(effects == [.copy("hello")])
        #expect(rig.controller.state.inputSelection == nil)
        press(&rig, Key.left.rawValue)
        #expect(rig.controller.state.inputSelection != nil)
        #expect(rig.controller.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 10).isEmpty)
        #expect(rig.controller.state.inputSelection == nil)
    }

    @Test func `it takes over from a selection in the transcript, and control or alt make these other keys`() {
        var rig = rig("hello")
        _ = rig.drag(from: (9, 0), to: (9, 2))
        #expect(rig.controller.state.selection != nil)
        press(&rig, Key.left.rawValue)
        #expect(rig.controller.state.selection == nil && rig.controller.state.inputSelection != nil)
        var control = self.rig("hello")
        press(&control, Key.left.rawValue, control: true)
        #expect(control.controller.state.inputSelection == nil)
    }

    @Test func `a waiting question keeps the keys`() {
        var rig = rig("hello")
        rig.controller.handle(.askApproval(id: 1, question: "Run it?"))
        rig.draw()
        press(&rig, Key.left.rawValue)
        #expect(rig.controller.state.inputSelection == nil)
    }
}
