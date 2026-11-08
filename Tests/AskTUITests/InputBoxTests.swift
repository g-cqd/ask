internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// The input in a box (note n36, the owner's choices of 2026-11-08): rounded corners and a border down each side instead of rules from
/// edge to edge, in the session's colour, lighter (`ui.inputBorder` `tint`, the default), or the grey of secondary text (`dim`); the
/// command and file lists open above it.
@Suite("The input sits in a box with rounded corners, and the lists open above it")
struct InputBoxTests {
    private func rig(_ options: ScreenOptions = ScreenOptions(), draft: String = "hi", identity: String? = nil)
        -> PointerRig
    {
        var rig = PointerRig(columns: 30, rows: 12, options: options, lines: ["one", "two"])
        rig.controller.state.sessionIdentity = identity
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    @Test func `the box has rounded corners and a border down each side, and takes no more rows than the rules did`() {
        let rig = rig()
        let top = rig.composer.transcriptRows
        #expect(rig.text(row: top) == "╭" + String(repeating: "─", count: 28) + "╮")
        #expect(rig.text(row: top + 1) == "│ hi" + String(repeating: " ", count: 24) + " │")
        #expect(rig.text(row: top + 2) == "╰" + String(repeating: "─", count: 28) + "╯")
        #expect(rig.composer.transcriptRows == 12 - 1 - 1 - 2, "the input, the status and the box's two rows")
        #expect(rig.controller.frame.promptRow == top + 1 && rig.controller.frame.statusRow == top + 3)
    }

    @Test func `the draft and the cursor start inside the border`() {
        let rig = rig(draft: "hello")
        #expect(rig.cursor == (rig.composer.transcriptRows + 1, 7))
        let wide = self.rig(draft: String(repeating: "x", count: 30))
        let first = wide.composer.transcriptRows + 1
        #expect(
            wide.text(row: first) == "│ " + String(repeating: "x", count: 26) + " │",
            "the draft wraps inside the box"
        )
        #expect(wide.text(row: first + 1).hasPrefix("│ xxxx"))
    }

    @Test func `Up and Down move by the rows drawn inside the box, not by the screen's width`() {
        var rig = rig(draft: String(repeating: "x", count: 30) + "ab")
        _ = rig.controller.handle(.key(KeyEvent(keyCode: Key.up.rawValue)), pageRows: 10, columns: 30)
        #expect(rig.controller.state.editor.cursor == 32 - 26, "the box holds 26 columns of the draft")
    }

    @Test func `a click in the input lands on the character drawn under it`() {
        var rig = rig(draft: "hello")
        _ = rig.click(row: rig.controller.frame.promptRow, col: 4)
        #expect(rig.controller.state.editor.cursor == 2)
    }

    @Test
    func
        `the border is the session's colour, lighter, by default, and the grey of secondary text without one or when asked`()
    {
        let tinted = rig(identity: "session-a")
        let top = tinted.composer.transcriptRows
        guard case .rgb = tinted.buffer[top, 0].style.fg else {
            Issue.record("the border is in the session's colour: \(tinted.buffer[top, 0].style)")
            return
        }
        #expect(tinted.buffer[top + 1, 0].style.fg == tinted.buffer[top, 0].style.fg, "the sides too")
        #expect(tinted.buffer[top + 1, 2].style.fg == .default, "the draft keeps the text colour")
        let plain = rig()
        var dim = ScreenOptions()
        dim.inputBorder = .dim
        #expect(plain.buffer[top, 0].style == rig(dim, identity: "session-a").buffer[top, 0].style)
        #expect(plain.buffer[top, 0].style.dim || plain.buffer[top, 0].style.fg != .default)
    }

    @Test func `the command list opens above the box`() {
        var rig = rig(draft: "")
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(UInt8(ascii: "/")))), pageRows: 10)
        rig.draw()
        let box = rig.controller.frame.promptRow - 1
        #expect(rig.text(row: box).hasPrefix("╭"))
        #expect((rig.composer.transcriptRows ..< box).contains { rig.text(row: $0).contains("help") })
    }

    @Test func `with ui.separator off there is no box`() {
        let rig = rig(ScreenOptions(separator: false))
        #expect(rig.text(row: rig.composer.transcriptRows) == "hi")
        #expect(rig.cursor.column == 2)
    }
}
