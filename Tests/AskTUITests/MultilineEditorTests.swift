import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// A prompt can be several lines: pasted, typed with a newline key, and edited line by line.
@Suite("The prompt editor holds several lines and edits them by line")
struct MultilineEditorTests {
    private func key(_ code: UInt32, _ modifiers: KeyModifiers = []) -> KeyEvent {
        KeyEvent(keyCode: code, modifiers: modifiers)
    }
    private func type(_ text: String, into editor: inout PromptEditor) {
        for scalar in text.unicodeScalars { _ = editor.apply(key(scalar.value)) }
    }
    private let up = Key.up.rawValue
    private let down = Key.down.rawValue

    @Test func `a paste keeps its line breaks, with every kind normalised to one`() {
        var editor = PromptEditor()
        editor.paste("one\ntwo\r\nthree\rfour")
        #expect(editor.text == "one\ntwo\nthree\nfour")
    }

    @Test func `Shift-Enter and Ctrl-J insert a newline, Enter submits the whole prompt`() {
        var editor = PromptEditor()
        type("a", into: &editor)
        #expect(editor.apply(key(0x0D, .shift)) == .edited)
        type("b", into: &editor)
        #expect(editor.apply(key(0x0A)) == .edited)
        type("c", into: &editor)
        #expect(editor.text == "a\nb\nc")
        #expect(editor.apply(key(0x0D)) == .submitted("a\nb\nc"))
        #expect(editor.text.isEmpty)
    }

    @Test func `a lone newline is not a prompt`() {
        var editor = PromptEditor()
        _ = editor.apply(key(0x0D, .shift))
        #expect(editor.apply(key(0x0D)) == .ignored)
    }

    @Test func `up and down move between lines and keep the column where they can`() {
        var editor = PromptEditor()
        editor.paste("abcdef\nxy\nghijkl")
        _ = editor.apply(key(Key.left.rawValue))  // before the last l: column 5
        #expect(editor.apply(key(up)) == .edited)
        #expect(editor.cursor == "abcdef\nxy".count, "a short line clamps the column to its end")
        _ = editor.apply(key(up))
        #expect(editor.cursor == 5, "the wanted column 5 returns once a line can hold it")
        #expect(editor.apply(key(up)) == .ignored, "no line above the first")
        _ = editor.apply(key(down))
        _ = editor.apply(key(down))
        #expect(editor.apply(key(down)) == .ignored, "no line below the last")
    }

    @Test func `the column is remembered across a short line`() {
        var editor = PromptEditor()
        editor.paste("abcdef\nxy\nghijkl")
        _ = editor.apply(key(Key.left.rawValue))
        _ = editor.apply(key(up))
        _ = editor.apply(key(up))
        _ = editor.apply(key(down))
        _ = editor.apply(key(down))
        #expect(editor.cursor == "abcdef\nxy\nghijk".count)
    }

    @Test func `moving sideways forgets the remembered column`() {
        var editor = PromptEditor()
        editor.paste("abcdef\nxy\nghijkl")
        _ = editor.apply(key(Key.left.rawValue))  // column 5
        _ = editor.apply(key(up))  // clamped to column 2 on "xy"
        _ = editor.apply(key(Key.left.rawValue))  // now column 1
        _ = editor.apply(key(up))
        #expect(editor.cursor == 1, "the column is where the cursor is, not the one wanted before moving sideways")
    }

    @Test func `Home, End, Ctrl-A and Ctrl-E act on the line, not the prompt`() {
        var editor = PromptEditor()
        editor.paste("one\ntwo\nthree")
        _ = editor.apply(key(up))
        _ = editor.apply(key(Key.end.rawValue))
        #expect(editor.cursor == "one\ntwo".count)
        _ = editor.apply(key(Key.home.rawValue))
        #expect(editor.cursor == "one\n".count)
        _ = editor.apply(key(0x05))
        #expect(editor.cursor == "one\ntwo".count)
        _ = editor.apply(key(0x01))
        #expect(editor.cursor == "one\n".count)
    }

    @Test func `Ctrl-U and Ctrl-K delete within the line`() {
        var editor = PromptEditor()
        editor.paste("one\ntwo three\nfour")
        _ = editor.apply(key(up))  // column 4 of "two three": before "three"
        _ = editor.apply(key(0x0B))
        #expect(editor.text == "one\ntwo \nfour")
        _ = editor.apply(key(0x15))
        #expect(editor.text == "one\n\nfour" && editor.cursor == "one\n".count)
    }

    @Test func `Ctrl-K at the end of a line joins the next one`() {
        var editor = PromptEditor()
        editor.paste("one\ntwo")
        _ = editor.apply(key(up))
        _ = editor.apply(key(Key.end.rawValue))
        _ = editor.apply(key(0x0B))
        #expect(editor.text == "onetwo")
    }

    @Test func `Backspace joins lines and word deletion stops at a line break`() {
        var editor = PromptEditor()
        editor.paste("one\ntwo")
        _ = editor.apply(key(0x01))
        _ = editor.apply(key(0x7F))
        #expect(editor.text == "onetwo" && editor.cursor == 3)
        var words = PromptEditor()
        words.paste("alpha beta\ngamma")
        _ = words.apply(key(0x17))
        #expect(words.text == "alpha beta\n")
        _ = words.apply(key(0x17))
        #expect(words.text == "alpha ", "the break counts as the space before the word")
    }

    @Test func `a returned multi-line draft keeps its lines`() {
        var editor = PromptEditor()
        editor.restore("first\n\nsecond")
        #expect(editor.text == "first\n\nsecond" && editor.cursor == editor.text.count)
    }

    // MARK: - Layout

    private func rows(_ buffer: ScreenBuffer) -> [String] {
        (0 ..< buffer.rows)
            .map { row in
                var line = String(
                    (0 ..< buffer.columns)
                        .compactMap { column -> Character? in
                            let cell = buffer[row, column]
                            return cell.isContinuation ? nil : cell.character
                        })
                while line.last == " " { line.removeLast() }
                return line
            }
    }

    @Test func `the prompt draws each line on its own row and the cursor follows the editing line`() {
        var state = ScreenState(label: "m")
        state.editor.paste("one\ntwo")
        _ = state.editor.apply(key(up))
        _ = state.editor.apply(key(Key.home.rawValue))
        _ = state.editor.apply(key(Key.right.rawValue))
        var buffer = ScreenBuffer(columns: 20, rows: 6)
        var composer = ScreenComposer()
        let cursor = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).suffix(2)) == ["ask> one", "two"])
        #expect(cursor.row == 4 && cursor.column == 6, "on the first line, after its first letter")
    }

    @Test func `a tall prompt scrolls to keep the cursor visible`() {
        var state = ScreenState(label: "m")
        state.editor.paste((1 ... 10).map { "line \($0)" }.joined(separator: "\n"))
        var buffer = ScreenBuffer(columns: 20, rows: 18)
        var composer = ScreenComposer()
        let cursor = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).suffix(6)) == (5 ... 10).map { "line \($0)" })
        #expect(cursor.row == 17)
        for _ in 0 ..< 9 { _ = state.editor.apply(key(up)) }
        _ = composer.compose(state, into: &buffer)
        #expect(rows(buffer)[12] == "ask> line 1", "the viewport follows the cursor back to the top")
    }

    @Test func `an empty line in the prompt is drawn, not skipped`() {
        var state = ScreenState(label: "m")
        state.editor.paste("a\n\nb")
        var buffer = ScreenBuffer(columns: 20, rows: 9)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).suffix(3)) == ["ask> a", "", "b"])
    }
}
