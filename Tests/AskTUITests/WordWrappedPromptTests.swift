internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// n57: the input uses one word-aware source map for paint, navigation, clicking and selection, without adding source newlines.
@Suite("The input box wraps at word boundaries")
struct WordWrappedPromptTests {
    @Test func `the renderer moves a word whole and keeps the original prompt`() {
        var editor = PromptEditor()
        editor.paste("hello world")
        var prompt = PromptLayout()
        let frame = prompt.frame(editor, prompt: "", columns: 8, screenRows: 24, maximumRows: 6)
        #expect(frame.lines == ["hello ", "world"])
        #expect(frame.cursor == .init(row: 1, column: 5))
        #expect(editor.text == "hello world")
    }

    @Test func `vertical navigation uses the same word breaks as painting`() {
        var editor = PromptEditor()
        editor.paste("hello world")
        #expect(editor.apply(KeyEvent(keyCode: Key.up.rawValue), columns: 8) == .edited)
        #expect(editor.cursor == 5)
        #expect(editor.apply(KeyEvent(keyCode: Key.down.rawValue), columns: 8) == .edited)
        #expect(editor.cursor == 11)
    }

    @Test func `a word-wrapped input clicks and copies by source offsets inside its border`() {
        var rig = PointerRig(columns: 20, rows: 24, options: ScreenOptions(prompt: "ask> ", tint: false))
        rig.controller.state.editor.paste("hello wonderful world")
        rig.draw()
        let frame = rig.controller.frame
        let layout = frame.prompt!
        #expect(layout.rows == ["hello ", "wonderful world"])
        rig.click(row: frame.promptRow + 1, col: frame.promptColumn + 3)
        #expect(rig.controller.state.editor.cursor == 9)
        #expect(rig.controller.state.editor.text == "hello wonderful world")
        #expect(layout.offset(atRow: 1, column: 0) == 6)
        let effects = rig.drag(
            from: (frame.promptRow, frame.promptColumn + 8),
            to: (frame.promptRow + 1, frame.promptColumn + 2)
        )
        #expect(effects == [.copy("lo won")], "a soft wrap contributes no newline to the copied source")
    }

    @Test func `resizing recalculates word breaks without changing selected text`() {
        var editor = PromptEditor()
        editor.paste("hello world again")
        var prompt = PromptLayout()
        let narrow = prompt.frame(editor, prompt: "", columns: 8, screenRows: 30, maximumRows: 8, selection: 3 ..< 13)
        let wide = prompt.frame(editor, prompt: "", columns: 20, screenRows: 30, maximumRows: 8, selection: 3 ..< 13)
        #expect(narrow.lines == ["hello ", "world ", "again"])
        #expect(wide.lines == ["hello world again"])
        #expect(narrow.highlights == [3 ..< 6, 0 ..< 6, 0 ..< 1])
        #expect(wide.highlights == [3 ..< 13])
        #expect(String(editor.text.dropFirst(3).prefix(10)) == "lo world a")
    }

    /// TerminalKit a9e4b65 (the review of 2026-11-11): its own test is red on the revision before; this pins what ask draws with it.
    @Test func `a word that would end in the last cell leaves it for its space, so no row starts with one`() {
        var editor = PromptEditor()
        editor.paste("hello world foo")
        var prompt = PromptLayout()
        #expect(
            prompt.frame(editor, prompt: "", columns: 11, screenRows: 24, maximumRows: 6).lines == [
                "hello ", "world foo"
            ]
        )
    }
}
