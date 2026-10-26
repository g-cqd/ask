internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

@Suite("Prompt navigation follows the display rows the renderer uses")
struct WrappedPromptNavigationTests {
    private let up = KeyEvent(keyCode: Key.up.rawValue)
    private let down = KeyEvent(keyCode: Key.down.rawValue)

    @Test func `up and down cross a soft wrap and retain the wanted cell column`() {
        var editor = PromptEditor()
        editor.paste("abcdefghij")
        #expect(editor.apply(up, columns: 8, firstRowIndent: 5) == .edited)
        #expect(editor.cursor == 2)
        #expect(editor.apply(up, columns: 8, firstRowIndent: 5) == .ignored)
        #expect(editor.apply(down, columns: 8, firstRowIndent: 5) == .edited)
        #expect(editor.cursor == 10)
    }

    @Test func `a move at the soft boundary starts from its following display row`() {
        var editor = PromptEditor()
        editor.paste("abcd")
        _ = editor.apply(KeyEvent(keyCode: Key.left.rawValue))
        _ = editor.apply(up, columns: 8, firstRowIndent: 5)
        #expect(editor.cursor == 0)
        _ = editor.apply(down, columns: 8, firstRowIndent: 5)
        #expect(editor.cursor == 3)
    }

    @Test func `a wanted column inside a wide character snaps before the whole grapheme`() {
        var editor = PromptEditor()
        editor.paste("日本語abcdef")
        _ = editor.apply(up, columns: 10, firstRowIndent: 5)
        #expect(editor.cursor == 1)
        _ = editor.apply(down, columns: 10, firstRowIndent: 5)
        #expect(editor.cursor == 9)
    }

    @Test func `the wanted display column survives a short hard line`() {
        var editor = PromptEditor()
        editor.paste("abcdefgh\nx\nabcdefgh")
        _ = editor.apply(up, columns: 10)
        #expect(editor.cursor == 10)
        _ = editor.apply(up, columns: 10)
        #expect(editor.cursor == 8)
        _ = editor.apply(down, columns: 10)
        _ = editor.apply(down, columns: 10)
        #expect(editor.cursor == 19)
    }

    @Test func `a resize resets the old wanted column to the newly drawn cell`() {
        var editor = PromptEditor()
        editor.paste("abcdefghij")
        _ = editor.apply(up, columns: 8, firstRowIndent: 5)
        _ = editor.apply(down, columns: 6, firstRowIndent: 5)
        #expect(editor.cursor == 8)
    }

    @Test func `insertion after a visual move preserves the whole unwrapped prompt`() {
        var editor = PromptEditor()
        editor.paste("abcdefghij")
        _ = editor.apply(up, columns: 8, firstRowIndent: 5)
        _ = editor.apply(KeyEvent(keyCode: 0x58), columns: 8, firstRowIndent: 5)
        #expect(editor.apply(KeyEvent(keyCode: 0x0D), columns: 8, firstRowIndent: 5) == .submitted("abXcdefghij"))
    }

    @Test func `the controller passes its display width and prefix to navigation`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.state.editor.paste("abcdefghij")
        _ = controller.handle(.key(up), pageRows: 10, columns: 8)
        #expect(controller.state.editor.cursor == 2)
        _ = controller.handle(.key(down), pageRows: 10, columns: 6)
        #expect(controller.state.editor.cursor == 8)
    }

    @Test(arguments: [KeyEvent(keyCode: 0x18), KeyEvent(keyCode: 0x78, modifiers: .ctrl)])
    func `control X clears the entire draft rather than only one line`(key: KeyEvent) {
        var editor = PromptEditor()
        editor.paste("first\nsecond\nthird")
        #expect(editor.apply(key) == .edited)
        #expect(editor.text.isEmpty && editor.cursor == 0)
        #expect(editor.apply(key) == .ignored)
    }
}
