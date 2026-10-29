internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// Assistant messages drawn as Markdown (roadmap 0065, phase 4; `ui.markdown`): marks become styles, a selection still copies what the model wrote,
/// and a long code block folds to a line as it does with Markdown off.
@Suite("An assistant message is drawn as Markdown and copied as written")
struct MarkdownTranscriptTests {
    private static let options = ScreenOptions(
        codeFoldLines: 3, prompt: "ask> ", tint: false, separator: false, padding: false)
    private static let reply = "intro\n```swift\na\nb\nc\nd\n```\nafter"

    private func rows(_ rig: PointerRig) -> [String] { (0 ..< rig.buffer.rows).map { rig.text(row: $0) } }

    private func row(_ rig: PointerRig, _ text: String) -> Int? { rows(rig).firstIndex(of: text) }

    private static func lines(_ message: String, columns: Int = 30, style: BlockStyle = .plain) -> [ScreenComposer.Line]
    {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.addAssistantText(message)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
    }

    @Test func `marks become styles: a heading in colour, bold text bold, a link a hyperlink`() {
        let lines = Self.lines("# Title\n\nSome **bold** and [docs](https://x.y).")
        #expect(lines.map(\.text) == ["Title", "", "Some bold and docs."])
        #expect(lines[0].accents.first?.style.bold == true)
        #expect(lines[2].accents.contains { $0.columns == 5 ..< 9 && $0.style.bold })
        #expect(lines[2].links == [PathLinks.Link(columns: 14 ..< 18, uri: "https://x.y")])
    }

    @Test func `a link to a path is a file link, without its line number`() {
        let lines = Self.lines("See [the file](~/a.swift:12:3).")
        #expect(lines[0].links.map(\.uri).first?.hasPrefix("file://") == true)
        #expect(lines[0].links.map(\.uri).first?.hasSuffix("/a.swift") == true)
        #expect(ScreenComposer.withoutLocation("/a/b.swift:12:3") == "/a/b.swift")
        #expect(ScreenComposer.withoutLocation("/a/b:c") == "/a/b:c")
    }

    @Test func `a selection across rows copies the Markdown it shows, markers and all`() {
        var rig = PointerRig(options: Self.options, updates: [.assistantText("Some **bold** text\nand `code` here")])
        guard let first = row(rig, "Some bold text"), row(rig, "and code here") == first + 1 else {
            Issue.record("\(rows(rig))")
            return
        }
        #expect(rig.drag(from: (first, 5), to: (first + 1, 7)) == [.copy("**bold** text\nand `code`")])
        #expect(rig.inverse(row: first) == Array(5 ... 13) && rig.inverse(row: first + 1) == Array(0 ... 7))
    }

    @Test func `a line the model ends is a row of its own, as it wrote it`() {
        #expect(Self.lines("one\ntwo **three**\n- a\n  b").map(\.text) == ["one", "two three", "", "• a", "  b"])
    }

    @Test func `a long block folds to a dim line, a click opens it under that line, and a click on the line folds it`()
    {
        var rig = PointerRig(options: Self.options, updates: [.assistantText(Self.reply)])
        guard let header = row(rig, "code · swift · 4 lines") else {
            Issue.record("\(rows(rig))")
            return
        }
        #expect(rig.buffer[header, 0].style.dim)
        #expect(Array(rows(rig)[header - 2 ... header + 2]) == ["intro", "", "code · swift · 4 lines", "", "after"])
        rig.click(row: header, col: 2)
        guard let open = row(rig, "code · swift · 4 lines") else {
            Issue.record("\(rows(rig))")
            return
        }
        #expect(Array(rows(rig)[open ... open + 4]) == ["code · swift · 4 lines", "  a", "  b", "  c", "  d"])
        rig.click(row: open + 2, col: 2, after: .seconds(2))
        #expect(row(rig, "  b") != nil)
        rig.click(row: open, col: 2, after: .seconds(2))
        #expect(row(rig, "  b") == nil && row(rig, "code · swift · 4 lines") != nil)
    }

    @Test func `a short block is drawn whole, under its language`() {
        let lines = Self.lines("```swift\nlet a = 1\n```")
        #expect(lines.map(\.text) == ["  swift", "  let a = 1"])
        #expect(lines[0].source == nil)
    }

    @Test func `with Markdown off the message is the text the model wrote`() {
        let rig = PointerRig(
            options: ScreenOptions(markdown: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            updates: [.assistantText("Some **bold**")])
        #expect(row(rig, "Some **bold**") != nil)
    }

    @Test func `every row fits its width, and every segment names text that is in its line`() {
        for message in PlainAssistantCharacterisationTests.messages {
            let hardLines = TranscriptContent.hardLines(of: message)
            for columns in 1 ... 100 {
                for style in [BlockStyle.plain, BlockStyle()] {
                    for line in Self.lines(message, columns: columns, style: style) {
                        let width = UnicodeWidth.displayWidth(of: line.text)
                        #expect(width <= Swift.max(columns, 2 + 2 * style.inset), "\(columns): \(line.text)")
                        for segment in line.segments {
                            #expect(hardLines.indices.contains(segment.line))
                            let length = hardLines.indices.contains(segment.line) ? hardLines[segment.line].count : 0
                            #expect(segment.firstOffset + segment.sourceCount <= length, "\(columns): \(segment)")
                            #expect(segment.col + UnicodeWidth.displayWidth(of: segment.text) <= width)
                        }
                    }
                }
            }
        }
    }
}
