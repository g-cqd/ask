internal import Foundation
internal import Synchronization
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// The pointer on the screen (TerminalKit roadmap 0016, 0017): a drag selects what was drawn, the selection is highlighted and copied,
/// the wheel scrolls, and none of it touches rows that did not change.
@Suite("The pointer selects, copies and scrolls")
struct PointerSelectionTests {
    // The transcript is bottom-aligned above the status line: with two items on 12 rows they are rows 8 and 9.
    private static let two = ["alpha beta gamma", "second line"]

    @Test func `a drag selects what is under it, highlights it, and copies it when released`() {
        var rig = PointerRig(lines: Self.two)
        let effects = rig.drag(from: (8, 0), to: (8, 4))
        #expect(effects == [.copy("alpha")])
        #expect(rig.inverse(row: 8) == [0, 1, 2, 3, 4])
        #expect(rig.inverse(row: 9).isEmpty)
    }

    @Test func `a drag backwards and across two items reads them in order`() {
        var rig = PointerRig(lines: Self.two)
        let effects = rig.drag(from: (9, 5), to: (8, 6))
        #expect(effects == [.copy("beta gamma\nsecond")])
        #expect(rig.inverse(row: 8) == Array(6 ..< 16))
        #expect(rig.inverse(row: 9) == Array(0 ..< 6))
    }

    @Test func `a prompt begins at column zero and its selection matches the text`() {
        var rig = PointerRig()
        rig.controller.handle(.userPrompt("hello world"))
        rig.draw()
        let effects = rig.drag(from: (9, 0), to: (9, 4))
        #expect(effects == [.copy("hello")])
        #expect(rig.inverse(row: 9) == [0, 1, 2, 3, 4])
    }

    @Test func `with copy on select off the selection is kept and nothing is copied`() {
        var rig = PointerRig(
            options: ScreenOptions(copyOnSelect: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: Self.two
        )
        let effects = rig.drag(from: (8, 0), to: (8, 4))
        #expect(effects.isEmpty)
        #expect(rig.inverse(row: 8) == [0, 1, 2, 3, 4])
    }

    @Test func `a double click takes the word, a triple click the line`() {
        var rig = PointerRig(lines: Self.two)
        rig.click(row: 8, col: 7)
        let word = rig.click(row: 8, col: 7, after: .milliseconds(100))
        #expect(word == [.copy("beta")])
        #expect(rig.inverse(row: 8) == [6, 7, 8, 9])
        let line = rig.click(row: 8, col: 7, after: .milliseconds(100))
        #expect(line == [.copy("alpha beta gamma")])
        #expect(rig.inverse(row: 8) == Array(0 ..< 16))
    }

    @Test func `a click clears the selection and copies nothing`() {
        var rig = PointerRig(lines: Self.two)
        rig.drag(from: (8, 0), to: (8, 4))
        let effects = rig.click(row: 9, col: 3)
        #expect(effects.isEmpty)
        #expect(rig.inverse(row: 8).isEmpty)
        #expect(rig.controller.state.selection == nil)
    }

    @Test func `typing clears the selection`() {
        var rig = PointerRig(lines: Self.two)
        rig.drag(from: (8, 0), to: (8, 4))
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(Character("x").asciiValue!))), pageRows: 10)
        rig.draw()
        #expect(rig.controller.state.selection == nil)
        #expect(rig.inverse(row: 8).isEmpty)
    }

    @Test func `a drag that starts in the prompt selects nothing`() {
        var rig = PointerRig(lines: Self.two)
        let effects = rig.drag(from: (11, 2), to: (8, 4))
        #expect(effects.isEmpty)
        #expect(rig.controller.state.selection == nil)
    }

    @Test func `with the mouse off, nothing the pointer does is heard`() {
        var rig = PointerRig(
            options: ScreenOptions(mouse: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: Self.two)
        #expect(rig.drag(from: (8, 0), to: (8, 4)).isEmpty)
        rig.mouse(.scrollUp, .press, row: 5, col: 5)
        #expect(rig.controller.state.selection == nil)
        #expect(rig.controller.state.scrollback == 0)
    }

    @Test func `a wide character is selected whole and highlights both its cells`() {
        var rig = PointerRig(lines: ["日本語 text"])
        let effects = rig.drag(from: (9, 0), to: (9, 1))
        #expect(effects == [.copy("日")])
        #expect(rig.inverse(row: 9) == [0, 1])
    }

    // MARK: - The wheel

    private static let long = (1 ... 40).map { "line \($0)" }

    @Test func `the wheel scrolls by the configured lines and stops at both ends`() {
        var rig = PointerRig(
            options: ScreenOptions(scrollLines: 4, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: Self.long)
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        #expect(rig.controller.state.scrollback == 4)
        rig.mouse(.scrollDown, .press, row: 3, col: 3)
        rig.mouse(.scrollDown, .press, row: 3, col: 3)
        #expect(rig.controller.state.scrollback == 0)
        for _ in 0 ..< 30 { rig.mouse(.scrollUp, .press, row: 3, col: 3) }
        // 40 lines in 10 transcript rows: the top is 30 lines back.
        #expect(rig.controller.state.scrollback == 30)
    }

    @Test func `a transcript shorter than the screen does not scroll`() {
        var rig = PointerRig(lines: Self.two)
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        #expect(rig.controller.state.scrollback == 0)
    }

    @Test func `a selection stays on its text while the wheel scrolls it`() {
        var rig = PointerRig(
            options: ScreenOptions(scrollLines: 2, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: Self.long)
        rig.drag(from: (9, 0), to: (9, 6))  // "line 40"
        #expect(rig.inverse(row: 9) == Array(0 ..< 7))
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        // Two lines back: "line 40" is two rows lower, off the transcript's end, and "line 39" is not selected.
        #expect(rig.inverse(row: 9).isEmpty)
        rig.mouse(.scrollDown, .press, row: 3, col: 3)
        #expect(rig.inverse(row: 9) == Array(0 ..< 7))
    }

    @Test func `a drag that reaches the top row scrolls up one line and keeps selecting`() {
        var rig = PointerRig(lines: Self.long)
        rig.mouse(.left, .press, row: 5, col: 0)
        rig.mouse(.left, .drag, row: 0, col: 3)
        #expect(rig.controller.state.scrollback == 1)
        rig.mouse(.left, .drag, row: 0, col: 3)
        #expect(rig.controller.state.scrollback == 2)
        let copied = rig.mouse(.left, .release, row: 0, col: 3)
        guard case .copy(let text) = copied.first else {
            Issue.record("nothing was copied")
            return
        }
        // Pressed on the "l" of "line 36" (row 5), released on column 3 of the top row, which two lines of scroll made "line 30":
        // from its "e" to the "l" under the press, the grapheme under the press included.
        #expect(text == "e 30\nline 31\nline 32\nline 33\nline 34\nline 35\nl", "\(text.debugDescription)")
    }

    // MARK: - The composer

    @Test func `extending a selection writes only the rows it touches`() throws {
        let connection = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: connection, columns: 80, rows: 24)
        var composer = ScreenComposer()
        var state = ScreenState(label: "m", options: .legacy)
        for index in 0 ..< 12 { state.transcript.addNotice("untouched line number \(index)", isError: false) }
        pipeline.beginFrame()
        composer.compose(state, into: pipeline)
        try pipeline.forceRedraw()

        // Select inside one item: block 11 is the last, bottom-aligned at row 21.
        state.selection = ContentSelection(
            anchor: ContentPosition(block: 11, line: 0, offset: 0), head: ContentPosition(block: 11, line: 0, offset: 9)
        )
        connection.clearOutput()
        pipeline.beginFrame()
        composer.compose(state, into: pipeline)
        try pipeline.flush()

        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(output.contains("untouched"), "the selected row was not rewritten")
        #expect(!output.contains("line number 3"), "a row that did not change was rewritten")
        #expect(!output.contains("line number 10"), "a row that did not change was rewritten")
    }

    @Test func `selection dirties its rows and the status instructions but no other transcript rows`() {
        var rig = PointerRig(lines: Self.long)
        rig.buffer.dirty.clear()
        rig.drag(from: (4, 0), to: (4, 3))
        #expect(Set(rig.buffer.dirty.dirtyRanges(columns: 30).map(\.row)) == [4, 11])
        rig.buffer.dirty.clear()
        rig.drag(from: (4, 0), to: (6, 3))
        #expect(Set(rig.buffer.dirty.dirtyRanges(columns: 30).map(\.row)).isSubset(of: [4, 5, 6, 11]))
    }
}
