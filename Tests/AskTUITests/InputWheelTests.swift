internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// The wheel over a draft too tall for its window scrolls the window and leaves the cursor alone.
@Suite("The wheel scrolls a tall input")
struct InputWheelTests {
    private static let ten = (1 ... 10).map { "line \($0)" }.joined(separator: "\n")

    /// Thirty columns on twelve rows: four input rows (rows 8 to 11) showing the last four lines of a ten-line draft.
    private func rig(_ draft: String = ten) -> PointerRig {
        var rig = PointerRig(lines: Self.two)
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    private static let two = ["one", "two"]

    private func wheel(_ rig: inout PointerRig, _ button: MouseButton, row: Int = 10) {
        rig.mouse(button, .press, row: row, col: 3)
    }

    @Test func `a step up shows the row above, and the cursor stays in the text and leaves the screen`() {
        var rig = rig()
        #expect([8, 9, 10, 11].map { rig.text(row: $0) } == ["line 7", "line 8", "line 9", "line 10"])
        let cursor = rig.controller.state.editor.cursor
        wheel(&rig, .scrollUp)
        #expect([8, 9, 10, 11].map { rig.text(row: $0) } == ["line 6", "line 7", "line 8", "line 9"])
        #expect(rig.controller.state.editor.cursor == cursor)
        #expect(!rig.composer.cursorIsVisible, "the cursor is on a row that is not drawn")
        #expect(rig.text(row: 7).hasPrefix("input 6–9 of 10") || rig.text(row: 7).contains("input 6–9 of 10"))
    }

    @Test func `the steps go one row at a time, stop at both ends, and bring the cursor back when it is in view`() {
        var rig = rig()
        for _ in 0 ..< 30 { wheel(&rig, .scrollUp) }
        #expect(rig.text(row: 8).hasSuffix("line 1") && rig.text(row: 8).hasPrefix("ask> "))
        #expect(rig.controller.state.promptScroll == 0)
        for _ in 0 ..< 30 { wheel(&rig, .scrollDown) }
        #expect([8, 11].map { rig.text(row: $0) } == ["line 7", "line 10"])
        #expect(rig.composer.cursorIsVisible)
        // Overshooting the end banked nothing: one step back is one row.
        wheel(&rig, .scrollUp)
        #expect(rig.text(row: 8) == "line 6")
    }

    @Test func `the wheel does not pass its steps to the transcript while the input can still take them`() {
        var rig = rig()
        for _ in 0 ..< 40 { wheel(&rig, .scrollUp) }
        #expect(rig.controller.state.scrollback == 0)
    }

    @Test func `a draft that fits has nothing to scroll, so the step goes to the transcript`() {
        var rig = PointerRig(lines: (1 ... 40).map { "row \($0)" })
        _ = rig.controller.handle(.paste("short"), pageRows: 10)
        rig.draw()
        wheel(&rig, .scrollUp, row: 11)
        #expect(rig.controller.state.promptScroll == nil)
        #expect(rig.controller.state.scrollback == 3)
    }

    @Test func `a step over the transcript scrolls the transcript, not the input`() {
        var rig = rig()
        rig.mouse(.scrollUp, .press, row: 2, col: 3)
        #expect(rig.controller.state.promptScroll == nil)
    }

    @Test func `any key puts the window back on the cursor`() {
        var rig = rig()
        for _ in 0 ..< 3 { wheel(&rig, .scrollUp) }
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("x").asciiValue!))), pageRows: 10)
        rig.draw()
        #expect(rig.controller.state.promptScroll == nil)
        #expect(rig.text(row: 11) == "line 10x" && rig.composer.cursorIsVisible)
    }

    @Test func `a cursor key, a paste and a shifted key each put the window back too`() {
        for event in [
            InputEvent.key(KeyEvent(keyCode: Key.left.rawValue)), .paste("x"),
            .key(KeyEvent(keyCode: Key.left.rawValue, modifiers: .shift))
        ] {
            var rig = rig()
            for _ in 0 ..< 3 { wheel(&rig, .scrollUp) }
            _ = rig.controller.handle(event, pageRows: 10, columns: 30)
            #expect(rig.controller.state.promptScroll == nil, "\(event)")
        }
    }

    @Test func `a click in a scrolled window places the cursor on the row that was drawn, and ends the scroll`() {
        var rig = rig()
        for _ in 0 ..< 2 { wheel(&rig, .scrollUp) }
        #expect(rig.text(row: 8) == "line 5")
        rig.click(row: 8, col: 2)
        let text = rig.controller.state.editor.text
        let line5 =
            text.split(separator: "\n", omittingEmptySubsequences: false)[..<4].joined(separator: "\n").count + 1
        #expect(rig.controller.state.editor.cursor == line5 + 2)
        #expect(rig.controller.state.promptScroll == nil)
    }

    @Test func `with the mouse off the wheel is not heard`() {
        var rig = PointerRig(options: ScreenOptions(mouse: false), lines: Self.two)
        _ = rig.controller.handle(.paste(Self.ten), pageRows: 10)
        rig.draw()
        wheel(&rig, .scrollUp)
        #expect(rig.controller.state.promptScroll == nil)
    }
}
