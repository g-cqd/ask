import Testing

@testable import AskTUI

/// Roadmap 0177, the owner's choice C: a code block in a reply is drawn inside a rule (the language on its corner, a rule down the
/// gutter, a closing corner); copying it copies the code.
@Suite("A reply's code block is drawn inside a rule")
struct CodeRuleTests {
    @Test func `the block opens on its language, keeps its lines after the rule, and closes`() {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.addAssistantText("Here:\n\n```swift\nlet a = 1\nprint(a)\n```\n\nDone.")
        let rows = ScreenComposer.lines(in: transcript, at: 0, columns: 60).map(\.text)
        let open = rows.firstIndex { $0.contains("╭─ swift") }
        #expect(open != nil, "\(rows)")
        if let open {
            #expect(rows[open + 1].contains("│ let a = 1") && rows[open + 2].contains("│ print(a)"))
            #expect(rows[open + 3].contains("╰─"))
        }
    }

    @Test func `a long code block's fold title is drawn as the rule's corner`() {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.setCodeFoldLines(2)
        transcript.addAssistantText("```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```")
        let folded = ScreenComposer.lines(in: transcript, at: 0, columns: 60).map(\.text)
        #expect(folded == ["╭─ swift · 3 lines"])
    }

    @Test(arguments: ["", "swift"])
    func `an open long block has one corner: its header, then the code in the gutter`(language: String) {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.setCodeFoldLines(2)
        transcript.addAssistantText("```\(language)\nMAIN-23897 one\ntwo\nthree\n```")
        transcript.toggleCodeFold(0, at: 0)
        let rows = ScreenComposer.lines(in: transcript, at: 0, columns: 60).map(\.text)
        #expect(rows.filter { $0.contains("╭") }.count == 1, "\(rows)")
        #expect(
            rows.first?.contains("3 lines") == true && rows.dropFirst().first?.contains("│ MAIN-23897") == true,
            "\(rows)"
        )
    }
}
