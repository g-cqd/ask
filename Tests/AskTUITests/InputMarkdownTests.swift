internal import TerminalKitInput
internal import TerminalKitMarkdown
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// Markdown colour in the input while typing (roadmap 0085 proposal 4, 0151): colour only, every character stays as typed, markers dimmed,
/// and with `ui.markdown` off the input is drawn as before.
@Suite("The draft is coloured as Markdown, and stays as typed")
struct InputMarkdownTests {
    private static let theme = MarkdownTheme.standard

    /// The style each character of `text` gets, by character offset; nil for a character drawn as plain text.
    private static func styles(_ text: String) -> [Style?] {
        var result = [Style?](repeating: nil, count: text.count)
        for span in InputMarkdown.spans(of: text) {
            for offset in span.characters { result[offset] = span.style }
        }
        return result
    }

    @Test func `emphasis, strong and code take their styles, and their markers are dimmed`() {
        let text = "a **b** _c_ `d`"
        let styles = Self.styles(text)
        #expect(styles[0] == nil, "plain text is plain")
        #expect(styles[2] == InputMarkdown.markerStyle && styles[3] == InputMarkdown.markerStyle, "the ** markers")
        #expect(styles[4]?.bold == true, "b is strong")
        #expect(styles[9]?.italic == true, "c is emphasis")
        #expect(styles[13] == Self.theme.code, "d is code")
        #expect(styles[12] == InputMarkdown.markerStyle && styles[14] == InputMarkdown.markerStyle, "the backticks")
    }

    @Test func `an ATX heading is coloured as a heading, its hashes dimmed`() {
        let styles = Self.styles("# Title")
        #expect(styles[0] == InputMarkdown.markerStyle)
        #expect(styles[2] == Self.theme.headings[0])
    }

    @Test func `a setext heading is not coloured, since its meaning comes from the line below`() {
        let styles = Self.styles("Title\n===")
        #expect(styles[0] == nil)
    }

    @Test func `a link's text is a link and its target is dimmed`() {
        let text = "[docs](https://x.y)"
        let styles = Self.styles(text)
        #expect(styles[1] == Self.theme.link)
        #expect(styles[8] == Self.theme.linkTarget)
    }

    @Test func `a fence's lines are code, the fence itself dimmed`() {
        let text = "```swift\nlet a = 1\n```"
        let styles = Self.styles(text)
        #expect(styles[0] == InputMarkdown.markerStyle)
        #expect(styles[9] == Self.theme.code, "the code line")
    }

    @Test func `plain prose has no spans, so it costs nothing to draw`() {
        #expect(InputMarkdown.spans(of: "just some words").isEmpty)
    }

    /// A long draft is parsed only around the rows shown (the cost of a keystroke is the window's, not the draft's): what it colours
    /// there must be what parsing the whole draft colours there, across fences, lists, quotes and headings.
    @Test(arguments: [0, 7, 11, 12, 21, 29, 40, 133, 268, 399, 649, 811, 1_200, 1_487])
    func `a window of a long draft is coloured as the whole draft colours it`(firstLine: Int) {
        let pieces = [
            "# Title", "Some **bold** text and `code`.", "", "- one", "- two **x**", "", "  continued item text", "",
            "```swift", "let a = \"**not bold**\"", "", "# not a heading", "```", "", "> quoted _it_", "", "plain line",
            "~~~", "inside", "~~~", "", "    indented code **no**", "", "1. first", "2. [link](https://x.y)", "",
            "- item", "", "    **deep** continuation", "    **more** continuation", ""
        ]
        let lines = (0 ..< 1_500).map { pieces[$0 % pieces.count] }
        let text = lines.joined(separator: "\n")
        #expect(text.utf8.count > InputMarkdown.wholeParseBytes, "the draft must be long enough to be parsed by window")
        let starts = lines.reduce(into: [0]) { $0.append($0.last! + $1.count + 1) }
        let visible = starts[firstLine] ..< starts[Swift.min(firstLine + 12, lines.count)]
        let full = InputMarkdown.spans(of: text).flatMap { span in span.characters.map { ($0, span.style) } }
            .filter { visible.contains($0.0) }
        let windowed = InputMarkdown.spans(of: text, visible: visible)
            .flatMap { span in span.characters.map { ($0, span.style) } }
            .filter { visible.contains($0.0) }
        #expect(
            windowed.map(\.0) == full.map(\.0) && windowed.map(\.1) == full.map(\.1),
            "lines \(firstLine) to \(firstLine + 12)")
    }

    @Test func `the screen draws the draft exactly as typed, with the marks coloured`() {
        var rig = PointerRig(options: ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false))
        _ = rig.controller.handle(.paste("say **hi**"), pageRows: 10)
        rig.draw()
        guard let row = (0 ..< rig.buffer.rows).first(where: { rig.text(row: $0) == "ask> say **hi**" }) else {
            Issue.record("\((0 ..< rig.buffer.rows).map { rig.text(row: $0) })")
            return
        }
        #expect(rig.buffer[row, 11].style.bold, "h of hi is bold")
        #expect(rig.buffer[row, 9].style.dim, "the first * is dimmed")
        #expect(!rig.buffer[row, 5].style.bold, "say is plain")
    }

    @Test func `with Markdown off the draft is plain`() {
        var rig = PointerRig(
            options: ScreenOptions(markdown: false, prompt: "ask> ", tint: false, separator: false, padding: false))
        _ = rig.controller.handle(.paste("say **hi**"), pageRows: 10)
        rig.draw()
        let row = (0 ..< rig.buffer.rows).first { rig.text(row: $0) == "ask> say **hi**" }
        #expect(row.map { !rig.buffer[$0, 11].style.bold && !rig.buffer[$0, 9].style.dim } == true)
    }
}
