internal import Foundation
internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// Markdown beyond the model's replies (roadmap 0151): the model's reasoning and the person's own messages are drawn as Markdown too, each
/// keeping its look (reasoning dim and italic, the person's message bold), a selection still copies what was written, and with `ui.markdown`
/// off both are drawn as before.
@Suite("Reasoning and the person's messages are drawn as Markdown")
struct MarkdownEverywhereTests {
    private static func lines(_ item: (inout Transcript) -> Void, markdown: Bool = true, columns: Int = 40)
        -> [ScreenComposer.Line]
    {
        var transcript = Transcript()
        transcript.setMarkdown(markdown)
        item(&transcript)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns)
    }

    private static func opened(_ text: String, markdown: Bool = true) -> [ScreenComposer.Line] {
        lines(
            { transcript in
                transcript.addThinkingText(text)
                transcript.finishRunProgress()
                _ = transcript.toggleFold(0)
            }, markdown: markdown)
    }

    @Test func `open reasoning draws its marks as styles, under its dim italic look`() {
        let rows = Self.opened("Plan **first** with `ls`\n\n- one\n- two")
        #expect(
            rows.map(\.text).map { $0.trimmingCharacters(in: .whitespaces) }.prefix(1).first?
                .hasPrefix("Plan first with ls") == true)
        #expect(rows.contains { $0.text.hasPrefix("• one") })
        #expect(!rows.contains { $0.text.contains("**") || $0.text.contains("`") })
        #expect(rows[0].style.dim && rows[0].style.italic)
        #expect(rows[0].accents.contains { $0.columns == 5 ..< 10 && $0.style.bold && $0.style.dim && $0.style.italic })
    }

    @Test func `open reasoning keeps its status on the first row`() {
        let rows = Self.opened("Plan **first**")
        let plain = Self.opened("Plan first", markdown: false)
        #expect(rows[0].text == plain[0].text, "the same first row: the text, then the metadata at the right edge")
    }

    @Test func `folded reasoning is still one line`() {
        let rows = Self.lines { transcript in
            transcript.addThinkingText("Plan **first**")
            transcript.finishRunProgress()
        }
        #expect(rows.count == 1 && rows[0].text.hasPrefix("Thinking..."))
    }

    @Test func `the person's message draws its marks as styles, and stays bold`() {
        let rows = Self.lines { $0.addUser("Fix `a.swift` and *then* **ship**") }
        let text = rows.map(\.text).first { !$0.isEmpty }
        #expect(text == "Fix a.swift and then ship")
        let row = rows.first { !$0.text.isEmpty }
        #expect(row?.style.bold == true)
        #expect(row?.accents.contains { $0.style.italic && $0.style.bold } == true, "emphasis on top of the bold look")
    }

    @Test func `the person's message keeps its lines, as typed`() {
        let rows = Self.lines { $0.addUser("one\ntwo") }.map(\.text).filter { !$0.isEmpty }
        #expect(rows == ["one", "two"])
    }

    @Test func `with Markdown off, reasoning and the person's message are drawn as written`() {
        #expect(Self.opened("Plan **first**", markdown: false).first?.text.hasPrefix("Plan **first**") == true)
        let user = Self.lines({ $0.addUser("a **b**") }, markdown: false).map(\.text).filter { !$0.isEmpty }
        #expect(user == ["a **b**"])
    }

    @Test func `a selection in the person's message copies what was typed, marks and all`() {
        var rig = PointerRig(
            options: ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false),
            updates: [.userPrompt("Some **bold** text")])
        guard let row = (0 ..< rig.buffer.rows).first(where: { rig.text(row: $0) == "Some bold text" }) else {
            Issue.record("\((0 ..< rig.buffer.rows).map { rig.text(row: $0) })")
            return
        }
        #expect(rig.drag(from: (row, 0), to: (row, 13)) == [.copy("Some **bold** text")])
    }
}
