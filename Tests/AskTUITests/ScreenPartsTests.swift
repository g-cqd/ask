import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// The interactive screen's pure parts: the line editor and the layout. Wrapping is TerminalKit's `TextWrap`,
/// tested there.
@Suite("The screen edits lines, and lays out transcript, status and prompt")
struct ScreenPartsTests {
    // MARK: - Editing

    private func key(_ code: UInt32, _ modifiers: KeyModifiers = []) -> KeyEvent {
        KeyEvent(keyCode: code, modifiers: modifiers)
    }
    private func type(_ text: String, into editor: inout PromptEditor) {
        for scalar in text.unicodeScalars { _ = editor.apply(key(scalar.value)) }
    }

    @Test func `typing, moving and deleting edit at the cursor`() {
        var editor = PromptEditor()
        type("helo", into: &editor)
        _ = editor.apply(key(Key.left.rawValue))
        type("l", into: &editor)
        #expect(editor.text == "hello" && editor.cursor == 4)
        _ = editor.apply(key(0x01))  // Ctrl-A
        _ = editor.apply(key(0x04))  // Ctrl-D deletes forward when the line is not empty
        #expect(editor.text == "ello" && editor.cursor == 0)
        _ = editor.apply(key(0x05))  // Ctrl-E
        _ = editor.apply(key(0x7F))
        #expect(editor.text == "ell")
    }

    @Test func `word and line deletion`() {
        var editor = PromptEditor()
        type("run the tests", into: &editor)
        _ = editor.apply(key(0x17))  // Ctrl-W
        #expect(editor.text == "run the ")
        _ = editor.apply(key(0x15))  // Ctrl-U
        #expect(editor.text.isEmpty && editor.cursor == 0)
    }

    @Test func `enter submits non-blank text and clears the line`() {
        var editor = PromptEditor()
        #expect(editor.apply(key(0x0D)) == .ignored)
        type("  ", into: &editor)
        #expect(editor.apply(key(0x0D)) == .ignored)
        type("go", into: &editor)
        #expect(editor.apply(key(0x0D)) == .submitted("  go"))
        #expect(editor.text.isEmpty)
    }

    @Test func `control keys report intent instead of editing`() {
        var editor = PromptEditor()
        #expect(editor.apply(key(0x03)) == .interrupt)
        #expect(editor.apply(key(UInt32(Character("c").asciiValue!), .ctrl)) == .interrupt)
        #expect(editor.apply(key(0x04)) == .endOfInput)
        #expect(editor.apply(key(0x1B)) == .escape)
        #expect(editor.apply(key(Key.up.rawValue)) == .ignored)
    }

    // MARK: - Layout

    private func rows(_ buffer: ScreenBuffer) -> [String] {
        (0 ..< buffer.rows)
            .map { row in
                String(
                    (0 ..< buffer.columns)
                        .compactMap { column -> Character? in
                            let cell = buffer[row, column]
                            return cell.isContinuation ? nil : cell.character
                        }
                )
                .trimmingTrailingSpaces
            }
    }

    @Test func `the transcript sits above the status line and the prompt, bottom-aligned`() {
        var state = ScreenState(label: "model")
        state.transcript.addUser("hi")
        state.transcript.addAssistantText("hello there")
        var buffer = ScreenBuffer(columns: 20, rows: 6)
        var composer = ScreenComposer()
        let cursor = composer.compose(state, into: &buffer)
        #expect(rows(buffer) == ["", "", "hi", "hello there", "model · ready", "ask>"])
        #expect(cursor.row == 5 && cursor.column == 5)
    }

    @Test func `older lines scroll off the top, and scrollback brings them back`() {
        var state = ScreenState(label: "m")
        for index in 1 ... 5 { state.transcript.addNotice("line \(index)", isError: false) }
        var buffer = ScreenBuffer(columns: 20, rows: 4)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).prefix(2)) == ["line 4", "line 5"])
        state.scrollback = 2
        _ = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).prefix(2)) == ["line 2", "line 3"])
    }

    @Test func `tools show their status, and a running state says how to stop`() {
        var state = ScreenState(label: "m")
        state.transcript.startTool(name: "bash", summary: "ls")
        state.running = true
        var buffer = ScreenBuffer(columns: 40, rows: 3)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        #expect(rows(buffer)[0] == "bash ls …")
        #expect(rows(buffer)[1] == "m · working… (ctrl+c to stop)")
        state.transcript.finishTool(.failed("exit 1"))
        state.running = false
        _ = composer.compose(state, into: &buffer)
        #expect(rows(buffer)[0] == "bash ls ✗ exit 1")
    }

    @Test func `a long prompt wraps and the cursor follows it`() {
        var state = ScreenState(label: "m")
        state.editor.paste(String(repeating: "x", count: 20))
        var buffer = ScreenBuffer(columns: 10, rows: 9)
        var composer = ScreenComposer()
        let cursor = composer.compose(state, into: &buffer)
        #expect(Array(rows(buffer).suffix(3)) == ["ask> xxxxx", "xxxxxxxxxx", "xxxxx"])
        #expect(cursor.row == 8 && cursor.column == 5)
    }

    @Test func `composing an unchanged screen again writes nothing`() {
        var state = ScreenState(label: "m")
        for index in 1 ... 30 { state.transcript.addNotice("line \(index)", isError: false) }
        var buffer = ScreenBuffer(columns: 40, rows: 10)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        buffer.dirty.clear()
        _ = composer.compose(state, into: &buffer)
        #expect(buffer.dirty.isEmpty)
    }

    @Test func `a keystroke dirties only the prompt row`() {
        var state = ScreenState(label: "m")
        for index in 1 ... 30 { state.transcript.addNotice("line \(index)", isError: false) }
        var buffer = ScreenBuffer(columns: 40, rows: 10)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        buffer.dirty.clear()
        state.editor.paste("x")
        _ = composer.compose(state, into: &buffer)
        #expect(buffer.dirty.dirtyRanges(columns: 40).map(\.row) == [9])
        #expect(rows(buffer)[9] == "ask> x")
    }

    @Test func `a resize recomposes everything at the new width`() {
        var state = ScreenState(label: "m")
        state.transcript.addAssistantText("one two three four five")
        var composer = ScreenComposer()
        var wide = ScreenBuffer(columns: 30, rows: 4)
        _ = composer.compose(state, into: &wide)
        var narrow = ScreenBuffer(columns: 10, rows: 5)
        _ = composer.compose(state, into: &narrow)
        #expect(Array(rows(narrow).prefix(3)) == ["one two", "three four", "five"])
    }

    @Test func `after reset, a fresh buffer of the same size is drawn in full`() {
        var state = ScreenState(label: "m")
        state.transcript.addAssistantText("hello")
        var composer = ScreenComposer()
        var first = ScreenBuffer(columns: 20, rows: 3)
        _ = composer.compose(state, into: &first)
        var second = ScreenBuffer(columns: 20, rows: 3)
        composer.reset()
        _ = composer.compose(state, into: &second)
        #expect(rows(second)[0] == "hello")
    }

    @Test func `a streamed delta re-wraps only the item it extends`() {
        var state = ScreenState(label: "m")
        state.transcript.addAssistantText("first")
        state.transcript.addUser("next")
        state.transcript.addAssistantText("a")
        var buffer = ScreenBuffer(columns: 20, rows: 8)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        let revisionsBefore = state.transcript.revisions
        state.transcript.addAssistantText("b")
        #expect(Array(state.transcript.revisions.prefix(2)) == Array(revisionsBefore.prefix(2)))
        #expect(state.transcript.revisions[2] != revisionsBefore[2])
        _ = composer.compose(state, into: &buffer)
        #expect(rows(buffer)[5] == "ab")
    }
}

extension String {
    fileprivate var trimmingTrailingSpaces: String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
