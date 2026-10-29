internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// What an assistant message draws as with Markdown off: written before Markdown drawing existed (roadmap 0065, phase 4), so that `ui.markdown`
/// off is ask as it was, row for row. A change to any of these rows is a change to the off path, and must be deliberate.
@Suite("With Markdown off, an assistant message draws as it did before Markdown")
struct PlainAssistantCharacterisationTests {
    static let messages = [
        "# Title\n\nSome **bold** and *em* and `code`, a [link](https://example.com) and www.example.com.\n",
        "- one\n- two\n  - nested item with more words than fit\n\n1. first\n2. second\n",
        "> quoted text that goes on\n> > nested\n\n---\n\n| a | b |\n|---|---:|\n| 1 | two |\n",
        "intro\n```swift\nlet a = 1\n\tlet b = 2\nc\nd\n```\nafter &amp; tab\there\n",
        "日本語の文章はスペースなしで長く続きますので折り返しが必要です。 \u{1B}[31m red?\n\nline  \nbreak\\\nnext",
        "Footnote[^1] and ~~strike~~ and - [x] done.\n\n[^1]: the note\n\n```\nunclosed fence\n"
    ]

    /// Every row's text, style, source and accents, in one string, for a message at a width and a look.
    static func rendering(_ message: String, columns: Int, style: BlockStyle, foldLines: Int) -> String {
        var transcript = Transcript()
        transcript.setCodeFoldLines(foldLines)
        transcript.addAssistantText(message)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
            .map { line in
                let source = line.source.map { "\($0.line):\($0.offset):\($0.col):\($0.text)" } ?? "-"
                return
                    "\(line.text)|\(line.style)|\(source)|\(line.accents)|\(line.links)|\(line.foldBlock.map(String.init) ?? "-")"
            }
            .joined(separator: "\n")
    }

    /// FNV-1a over the renderings of every message at widths 1 to 100, plain and padded, with code folding at 2 and 20 lines.
    static func digest() -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for message in messages {
            for columns in 1 ... 100 {
                for style in [BlockStyle.plain, BlockStyle()] {
                    for foldLines in [2, 20] {
                        for byte in rendering(message, columns: columns, style: style, foldLines: foldLines).utf8 {
                            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
                        }
                        hash = (hash ^ 0x0A) &* 0x0000_0100_0000_01B3
                    }
                }
            }
        }
        return hash
    }

    @Test func `the rows of every message at every width are those ask drew before Markdown`() {
        #expect(Self.digest() == 5_925_546_613_186_270_904)
    }

    @Test func `a message draws as its wrapped source, markers and all, and a long fence folds to a dim line`() {
        var transcript = Transcript()
        transcript.setCodeFoldLines(2)
        transcript.addAssistantText(Self.messages[3])
        let lines = ScreenComposer.lines(in: transcript, at: 0, columns: 20, style: .plain)
        #expect(lines.map(\.text) == ["intro", "code · swift · 4", "lines", "after &amp; tab   ", "here", ""])
        #expect(lines[1].style == Style(dim: true))
    }
}
