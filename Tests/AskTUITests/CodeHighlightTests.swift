internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// Fenced code coloured by aemi's lexers (roadmap 0152, phase 2; `ui.highlight`): roles in the terminal's palette, a construct that runs
/// across lines coloured on each, and a language the lexers do not know drawn as with highlighting off.
@Suite("Fenced code is coloured by its language")
struct CodeHighlightTests {
    private static func lines(_ message: String, highlight: Bool = true) -> [ScreenComposer.Line] {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.setHighlight(highlight)
        transcript.addAssistantText(message)
        return ScreenComposer.lines(in: transcript, at: 0, columns: 60, style: .plain)
    }

    /// The colour of the accent over `columns` of the row that shows `text`.
    private static func colour(_ lines: [ScreenComposer.Line], row text: String, _ columns: Range<Int>) -> Color? {
        lines.first { $0.text == text }?.accents.first { $0.columns == columns }?.style.fg
    }

    @Test func `a keyword, a number, a string and a comment each take their colour`() {
        let lines = Self.lines("```swift\nlet a = 0x1F + \"s\" // c\n```")
        let row = "│ let a = 0x1F + \"s\" // c"
        #expect(Self.colour(lines, row: row, 2 ..< 5) == .indexed(5))
        #expect(Self.colour(lines, row: row, 10 ..< 14) == .indexed(3))
        #expect(Self.colour(lines, row: row, 17 ..< 20) == .indexed(2))
        #expect(lines.first { $0.text == row }?.accents.first { $0.columns == 21 ..< 25 }?.style.dim == true)
    }

    @Test func `a block comment that runs on colours the next line too`() {
        let lines = Self.lines("```rust\n/* open\nstill */ let x = 1;\n```")
        #expect(
            lines.first { $0.text == "│ still */ let x = 1;" }?.accents.first { $0.columns == 2 ..< 10 }?.style.dim
                == true
        )
        #expect(Self.colour(lines, row: "│ still */ let x = 1;", 11 ..< 14) == .indexed(5))
    }

    @Test func `a language named by an alias is found, and one the lexers do not know is plain`() {
        #expect(Self.colour(Self.lines("```sh\necho hi\n```"), row: "│ echo hi", 2 ..< 6) == .indexed(5))
        for message in ["```brainfuck\nlet ++\n```", "```\nlet a = 1\n```", "```text\nlet a = 1\n```"] {
            #expect(
                Self.lines(message).map(\.accents) == Self.lines(message, highlight: false).map(\.accents),
                "\(message)"
            )
        }
    }

    @Test func `highlighting on changes the rows the off digest pins`() {
        let message = CodeHighlightCharacterisationTests.messages[0]
        #expect(Self.lines(message).map(\.accents) != Self.lines(message, highlight: false).map(\.accents))
    }

    @Test func `the screen's option reaches the transcript, on by default`() {
        #expect(ScreenOptions().highlight)
        #expect(!ScreenOptions(highlight: false).highlight)
    }
}
