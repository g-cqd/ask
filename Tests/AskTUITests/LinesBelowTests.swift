internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// What the reader sees while text keeps arriving below them (ADR-0072): the view stays on what they were reading, the status line
/// says how many lines are below it, and a click, End on an empty draft or PageDown takes them there.
@Suite("A reader scrolled back stays where they are, and is told what is below")
struct LinesBelowTests {
    /// Twelve rows: ten of transcript, the prompt (row 10), the status line (row 11).
    private static let statusRow = 11

    private func rig(
        columns: Int = 40,
        options: ScreenOptions = ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false),
        lines: Int = 40, scrolled: Bool = true
    ) -> PointerRig {
        var rig = PointerRig(
            columns: columns, rows: 12, options: options, lines: (1 ... lines).map { "line \($0)" })
        if scrolled { rig.mouse(.scrollUp, .press, row: 3, col: 3) }
        return rig
    }

    private func transcript(_ rig: PointerRig) -> [String] { (0 ..< 10).map { rig.text(row: $0) } }

    private func key(_ code: Key, in rig: inout PointerRig, pageRows: Int = 9) {
        _ = rig.controller.handle(.key(KeyEvent(keyCode: code.rawValue)), pageRows: pageRows)
        rig.draw()
    }

    // MARK: - The view holds

    @Test func `text arriving below a reader who scrolled back does not move what they read`() {
        var rig = rig()
        let before = transcript(rig)
        let scrolledBy = rig.controller.state.scrollback
        #expect(scrolledBy > 0)
        _ = rig.controller.handle(.assistantText("new one\nnew two\nnew three"))
        rig.draw()
        #expect(transcript(rig) == before)
        #expect(rig.controller.state.scrollback == scrolledBy + 3)
    }

    @Test func `each further piece of the same reply holds the view too, wrapped lines included`() {
        var rig = rig()
        let before = transcript(rig)
        _ = rig.controller.handle(.assistantText("first"))
        // Words of seven letters: five fit on a row of forty columns and six on one of forty-seven, so the rows a piece takes depend on
        // the width it is wrapped at.
        let words = String(repeating: "abcdefg ", count: 24)
        for piece in [words, "\n" + words + words, "\nthen a line"] {
            _ = rig.controller.handle(.assistantText(piece))
            rig.draw()
            #expect(transcript(rig) == before, "after \(piece.count) more characters")
        }
    }

    @Test func `a reader at the end keeps following it`() {
        var rig = rig(scrolled: false)
        _ = rig.controller.handle(.assistantText("new one\nnew two"))
        rig.draw()
        #expect(rig.controller.state.scrollback == 0)
        #expect(rig.text(row: 9) == "new two")
    }

    @Test func `a new block below, a notice or a tool, holds the view as well`() {
        var rig = rig()
        let before = transcript(rig)
        _ = rig.controller.handle(.notice("a notice", isError: false))
        _ = rig.controller.handle(.toolStarted(name: "bash", summary: "ls"))
        _ = rig.controller.handle(.toolFinished(.succeeded, output: "a\nb\nc"))
        rig.draw()
        #expect(transcript(rig) == before)
    }

    @Test func `a reader inside the last block, with only part of it below, is held too`() {
        var rig = rig(lines: 3)
        _ = rig.controller.handle(.assistantText((1 ... 14).map { "answer \($0)" }.joined(separator: "\n")))
        rig.draw()
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        let before = transcript(rig)
        #expect(rig.controller.state.scrollback > 0 && rig.controller.state.scrollback < 14)
        _ = rig.controller.handle(.assistantText("\nanswer 15\nanswer 16"))
        rig.draw()
        #expect(transcript(rig) == before)
    }

    @Test func `an update that sends the reader to the end is not undone by the hold`() {
        var rig = rig()
        _ = rig.controller.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?"))
        #expect(rig.controller.state.scrollback == 0)
        var cleared = self.rig()
        _ = cleared.controller.handle(.clearConversation)
        #expect(cleared.controller.state.scrollback == 0)
    }

    @Test func `before any frame has been drawn there is no width to measure, and the position is left alone`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.handle(.notice("one", isError: false))
        controller.state.scrollback = 4
        controller.handle(.assistantText("more\nlines"))
        #expect(controller.state.scrollback == 4)
    }

    @Test func `a tail that shrinks by more than the reader is behind the end leaves them at the end, not below it`() {
        var rig = rig(lines: 3)
        rig.controller.handle(.notice("a\nb\nc\nd\ne", isError: false))
        rig.draw()
        rig.controller.state.scrollback = 1
        _ = rig.controller.holdingView { controller in
            controller.state.transcript.removeAll()
            return []
        }
        #expect(rig.controller.state.scrollback == 0)
    }

    // MARK: - The line

    @Test func `the status line counts the lines below, and says nothing at the end`() {
        var rig = rig(scrolled: false)
        #expect(rig.text(row: Self.statusRow) == "✓ · m")
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        let below = rig.controller.state.scrollback
        #expect(rig.text(row: Self.statusRow) == "✓ · m · \(below) lines below")
        rig.controller.state.scrollback = 1
        rig.draw()
        #expect(rig.text(row: Self.statusRow) == "✓ · m · 1 line below")
    }

    @Test func `the count sits before the jobs, and the jobs keep their click`() {
        var rig = rig()
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "sleep 9")]))
        rig.draw()
        let line = rig.text(row: Self.statusRow)
        #expect(line.hasPrefix("✓ · m · ") && line.hasSuffix(" lines below · 1 job"))
        let column = line.count - "1 job".count
        rig.click(row: Self.statusRow, col: column + 1)
        #expect(rig.controller.state.runnersOpen)
    }

    // MARK: - Getting there

    @Test func `a click on the count goes to the end, and a click elsewhere on the line does not`() {
        var rig = rig()
        let below = rig.controller.state.scrollback
        let end = rig.text(row: Self.statusRow).count
        for column in [0, 1, 2, 3, end, 38] {
            rig.click(row: Self.statusRow, col: column)
            #expect(rig.controller.state.scrollback == below, "column \(column), the count ends at \(end)")
        }
        rig.click(row: Self.statusRow, col: 10)
        #expect(rig.controller.state.scrollback == 0)
        #expect(rig.text(row: 9) == "line 40" && rig.text(row: Self.statusRow) == "✓ · m")
    }

    @Test func `with the mouse off the count is still shown and is not clicked`() {
        var rig = rig(
            options: ScreenOptions(mouse: false, prompt: "ask> ", tint: false, separator: false, padding: false))
        rig.controller.state.scrollback = 5
        rig.draw()
        #expect(rig.text(row: Self.statusRow) == "✓ · m · 5 lines below")
        rig.click(row: Self.statusRow, col: 10)
        #expect(rig.controller.state.scrollback == 5)
    }

    @Test func `End on an empty draft goes to the end`() {
        var rig = rig()
        key(.end, in: &rig)
        #expect(rig.controller.state.scrollback == 0)
    }

    @Test func `End in a draft with words in it is still the editor's`() {
        var rig = rig()
        let below = rig.controller.state.scrollback
        for scalar in "hello".unicodeScalars {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 9)
        }
        key(.home, in: &rig)
        key(.end, in: &rig)
        #expect(rig.controller.state.scrollback == below)
        #expect(rig.controller.state.editor.cursor == 5)
    }

    @Test func `End at the end of the conversation clears a selection, as any key in the prompt does`() {
        var rig = rig(scrolled: false)
        rig.drag(from: (2, 1), to: (2, 6))
        #expect(rig.controller.state.selection != nil)
        key(.end, in: &rig)
        #expect(rig.controller.state.selection == nil)
    }

    @Test func `PageDown still goes down a page at a time`() {
        var rig = rig()
        rig.controller.state.scrollback = 20
        key(.pageDown, in: &rig)
        #expect(rig.controller.state.scrollback == 11)
    }

    @Test func `a narrow screen clips the line and nothing breaks`() {
        var rig = rig(columns: 12)
        #expect(rig.text(row: Self.statusRow) == "✓ · m", "the count does not fit, so it is left out whole, not cut")
        rig.click(row: Self.statusRow, col: 11)
        #expect(rig.controller.state.scrollback > 0, "the count is not on the screen, so there is nothing to click")
    }
}
