internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// Option+Backspace deletes the word before the cursor, as Ctrl+W does (roadmap 0095). Terminals send it as ESC DEL, ESC BS, or with the
/// kitty protocol as `CSI 127;3u`.
@Suite("Option+Backspace deletes by word")
struct OptionBackspaceTests {
    private func decoded(_ bytes: String) -> [KeyEvent] {
        var router = SequenceRouter()
        return router.feedAll(Array(bytes.utf8))
            .compactMap {
                if case .key(let key) = $0 { return key }
                return nil
            }
    }

    private func editor(_ text: String) -> PromptEditor {
        var editor = PromptEditor()
        editor.paste(text)
        return editor
    }

    @Test(arguments: ["\u{1B}\u{7F}", "\u{1B}\u{08}", "\u{1B}[127;3u"])
    func `each encoding decodes to one key that deletes the last word`(bytes: String) {
        let keys = decoded(bytes)
        #expect(keys.count == 1)
        var editor = editor("hello brave world")
        for key in keys { _ = editor.apply(key) }
        #expect(editor.text == "hello brave ")
    }

    @Test func `it does the same as Ctrl+W`() {
        var option = editor("one two")
        var control = editor("one two")
        _ = option.apply(KeyEvent(keyCode: 0x7F, modifiers: .alt))
        _ = control.apply(KeyEvent(keyCode: 0x17))
        #expect(option.text == control.text)
    }

    @Test func `plain Backspace still deletes one character`() {
        var editor = editor("one two")
        _ = editor.apply(KeyEvent(keyCode: 0x7F))
        #expect(editor.text == "one tw")
    }

    @Test func `Option+Delete deletes the word after the cursor, and Delete one character`() {
        let delete = decoded("\u{1B}[3;3~")
        #expect(delete.count == 1)
        var editor = editor("one two three")
        editor.place(cursor: 3)
        for key in delete { _ = editor.apply(key) }
        #expect(editor.text == "one three")
        _ = editor.apply(KeyEvent(keyCode: PromptEditor.forwardDelete))
        #expect(editor.text == "onethree")
    }
}
