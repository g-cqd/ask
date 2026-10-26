internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// The input's look (roadmap 0074): no prefix unless one is asked for, a tinted background to the edge of the row, and a rule between the
/// conversation and the input; each can be turned off.
@Suite("The input is marked by its tint and a rule above it, not by a prefix")
struct InputLookTests {
    private func rig(_ options: ScreenOptions = ScreenOptions(), draft: String = "hi") -> PointerRig {
        var rig = PointerRig(columns: 30, rows: 12, options: options, lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    @Test func `by default there is no prefix, and the draft starts at the first column`() {
        let rig = rig()
        #expect(rig.text(row: rig.composer.transcriptRows + 1) == "hi")
        #expect(rig.cursor.column == 2)
    }

    @Test func `a prefix is whatever ui.prompt says`() {
        let rig = rig(ScreenOptions(prompt: "> "))
        #expect(rig.text(row: rig.composer.transcriptRows + 1) == "> hi")
        #expect(rig.cursor.column == 4)
    }

    @Test func `a rule separates the conversation from the input, and takes a row`() {
        let rig = rig()
        let rule = rig.composer.transcriptRows
        #expect(rig.text(row: rule) == String(repeating: "─", count: 30))
        #expect(rig.composer.transcriptRows == 12 - 1 - 1 - 1, "the input, the status and the rule")
        #expect(rig.controller.frame.promptRow == rule + 1 && rig.controller.frame.statusRow == rule + 2)
    }

    @Test func `with the rule off the input follows the conversation`() {
        let rig = rig(ScreenOptions(separator: false))
        #expect(rig.composer.transcriptRows == 12 - 2)
        #expect(rig.text(row: rig.composer.transcriptRows) == "hi")
    }

    @Test func `the input row is tinted to its edge, and the rows around it are not`() {
        let rig = rig()
        let input = rig.composer.transcriptRows + 1
        let tint = ScreenTheme().inputBackground
        #expect(tint != .default)
        #expect((0 ..< 30).allSatisfy { rig.buffer[input, $0].style.bg == tint }, "text and blanks alike")
        #expect(rig.buffer[input - 1, 0].style.bg == .default && rig.buffer[input + 1, 0].style.bg == .default)
    }

    @Test func `with the tint off nothing is painted`() {
        let rig = rig(ScreenOptions(tint: false))
        let input = rig.composer.transcriptRows + 1
        #expect((0 ..< 30).allSatisfy { rig.buffer[input, $0].style.bg == .default })
    }

    @Test func `a light terminal gets the lighter tint`() {
        #expect(ScreenTheme(light: true).inputBackground != ScreenTheme(light: false).inputBackground)
    }

    @Test func `a screen too short for a rule has none, so the transcript keeps its rows`() {
        var tiny = PointerRig(columns: 20, rows: 5, options: ScreenOptions(), lines: ["one", "two"])
        tiny.draw()
        #expect(!(0 ..< 5).contains { tiny.text(row: $0).hasPrefix("─") })
    }

    @Test func `a click on the rule is not a click on the input`() {
        var rig = rig()
        let before = rig.controller.state.editor.cursor
        rig.click(row: rig.composer.transcriptRows, col: 1)
        #expect(rig.controller.state.editor.cursor == before)
    }

    @Test func `the cursor is on the input, below the rule`() {
        let rig = rig()
        #expect(rig.cursor.row == rig.composer.transcriptRows + 1)
    }
}
