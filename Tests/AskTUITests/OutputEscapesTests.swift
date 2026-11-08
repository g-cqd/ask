import TerminalKitStyle
import Testing

@testable import AskTUI

/// A tool's output with its terminal escapes read (note n30): colours and links kept as spans, everything else removed whole, so nothing
/// a program writes reaches the terminal raw and no `[1;31m` is left in the text.
@Suite("A tool's escapes become styles, and the rest is removed")
struct OutputEscapesTests {
    private static let esc = "\u{1B}"

    @Test func `output with no escape is kept as it is, with no spans`() {
        let parsed = OutputEscapes("plain\n\tline\r\n")
        #expect(parsed.text == "plain\n\tline\r\n")
        #expect(parsed.lines.isEmpty)
    }

    @Test func `a colour and bold become a span over the plain text`() {
        let parsed = OutputEscapes("ok \(Self.esc)[1;31merror:\(Self.esc)[0m done")
        #expect(parsed.text == "ok error: done")
        #expect(parsed.lines == [[OutputEscapes.Span(bytes: 3 ..< 9, style: Style(fg: .indexed(1), bold: true))]])
    }

    @Test func `a style carries over a line feed, as a terminal keeps it`() {
        let parsed = OutputEscapes("\(Self.esc)[32mone\ntwo\(Self.esc)[39m three")
        #expect(parsed.text == "one\ntwo three")
        let green = Style(fg: .indexed(2))
        #expect(parsed.lines == [[.init(bytes: 0 ..< 3, style: green)], [.init(bytes: 0 ..< 3, style: green)]])
    }

    @Test func `bright, 256 and true colours, and the colon forms, are read`() {
        let parsed = OutputEscapes(
            "\(Self.esc)[91ma\(Self.esc)[38;5;208mb\(Self.esc)[38;2;1;2;3mc\(Self.esc)[38:2::4:5:6md\(Self.esc)[4:3me\(Self.esc)[m"
        )
        #expect(parsed.text == "abcde")
        #expect(
            parsed.lines[0].map(\.style) == [
                Style(fg: .indexed(9)), Style(fg: .indexed(208)), Style(fg: .rgb(r: 1, g: 2, b: 3)),
                Style(fg: .rgb(r: 4, g: 5, b: 6)), Style(fg: .rgb(r: 4, g: 5, b: 6), underline: .curly)
            ]
        )
    }

    @Test func `dim, italic, underline and strikethrough are kept, and switched off one by one`() {
        let parsed = OutputEscapes("\(Self.esc)[2;3;4;9ma\(Self.esc)[22;23mb\(Self.esc)[24;29mc")
        #expect(parsed.text == "abc")
        #expect(
            parsed.lines == [
                [
                    .init(
                        bytes: 0 ..< 1,
                        style: Style(dim: true, italic: true, underline: .single, strikethrough: true)
                    ),
                    .init(bytes: 1 ..< 2, style: Style(underline: .single, strikethrough: true))
                ]
            ]
        )
    }

    @Test func `a background is not drawn: the block's own shows`() {
        let parsed = OutputEscapes("\(Self.esc)[41;37mx\(Self.esc)[0m")
        #expect(parsed.lines == [[.init(bytes: 0 ..< 1, style: Style(fg: .indexed(7)))]])
    }

    @Test func `cursor moves, clears, titles, the clipboard, DCS and APC are removed whole`() {
        let raw =
            "a\(Self.esc)[2K\(Self.esc)[1A\(Self.esc)]0;title\u{07}b\(Self.esc)]52;c;ZXZpbA==\(Self.esc)\\c"
            + "\(Self.esc)P1$r\(Self.esc)\\d\(Self.esc)_Gf=100;AAAA\(Self.esc)\\e\(Self.esc)[?25lf\(Self.esc)7g\u{07}h\u{08}i"
        let parsed = OutputEscapes(raw)
        #expect(parsed.text == "abcdefghi")
        #expect(parsed.lines.allSatisfy { $0.isEmpty })
    }

    @Test func `the 8-bit forms are removed too`() {
        let parsed = OutputEscapes("a\u{9B}31mb\u{9D}0;t\u{9C}c\u{85}d")
        #expect(parsed.text == "abcd")
        #expect(parsed.lines == [[.init(bytes: 1 ..< 4, style: Style(fg: .indexed(1)))]])
    }

    @Test func `a web link is kept, and a link to anything else is dropped with its text kept`() {
        let parsed = OutputEscapes(
            "\(Self.esc)]8;;https://example.com/a\(Self.esc)\\site\(Self.esc)]8;;\(Self.esc)\\ "
                + "\(Self.esc)]8;id=x;javascript:alert(1)\u{07}bad\(Self.esc)]8;;\u{07}"
        )
        #expect(parsed.text == "site bad")
        #expect(parsed.lines == [[.init(bytes: 0 ..< 4, style: Style(link: "https://example.com/a"))]])
    }

    @Test func `a link with a space or a control in it is dropped`() {
        let parsed = OutputEscapes("\(Self.esc)]8;;https://a.com/x y\(Self.esc)\\t\(Self.esc)]8;;\(Self.esc)\\")
        #expect(parsed.text == "t")
        #expect(parsed.lines.allSatisfy { $0.isEmpty })
    }

    @Test func `a sequence that never ends gives up at the line feed, and the next line is shown`() {
        let parsed = OutputEscapes("a\(Self.esc)]0;never ends\nnext")
        #expect(parsed.text == "a\nnext")
    }

    @Test func `a sequence longer than any real one is given up, and what follows is shown`() {
        let parsed = OutputEscapes("\(Self.esc)[" + String(repeating: "1;", count: 3_000) + "mtail")
        #expect(parsed.text.hasSuffix("tail"))
        #expect(!parsed.text.contains("\u{1B}"))
    }

    @Test func `an empty parameter resets, and a number too long to be one is ignored`() {
        let reset = OutputEscapes("\(Self.esc)[31ma\(Self.esc)[mb\(Self.esc)[31;mc")
        #expect(reset.lines == [[.init(bytes: 0 ..< 1, style: Style(fg: .indexed(1)))]])
        let long = OutputEscapes("\(Self.esc)[31ma\(Self.esc)[1234567mb")
        #expect(long.lines == [[.init(bytes: 0 ..< 2, style: Style(fg: .indexed(1)))]])
    }

    @Test func `controls are removed from output that has no escape at all`() {
        let parsed = OutputEscapes("a\u{07}b\u{08}c\u{7F}d\u{00}e")
        #expect(parsed.text == "abcde")
        #expect(parsed.lines.allSatisfy { $0.isEmpty })
    }

    @Test func `a string ended by BEL ends there`() {
        #expect(OutputEscapes("a\(Self.esc)_Gf=100\u{07}b\(Self.esc)P1$r\u{07}c").text == "abc")
    }

    @Test func `spans count bytes, so text before a colour may be wide`() {
        let parsed = OutputEscapes("é漢\(Self.esc)[31mx")
        #expect(parsed.text == "é漢x")
        #expect(parsed.lines == [[.init(bytes: 5 ..< 6, style: Style(fg: .indexed(1)))]])
    }
}
