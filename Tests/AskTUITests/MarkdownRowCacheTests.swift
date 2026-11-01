internal import Testing

@testable import AskTUI

/// A message's blocks keep their rows between layouts while it streams in (roadmap 0152): what a warm transcript draws after each delta
/// is what a fresh one with the same text draws, and a block that has streamed past is not laid out again.
@Suite("Streamed Markdown keeps its blocks' rows, drawn as a fresh layout draws them")
struct MarkdownRowCacheTests {
    /// Pieces whose meaning a later line changes: a definition after its link, a setext underline, a list turning loose, a fence
    /// closing, a lazy continuation, a mark joining the character before it, a line ending split in two.
    static let alphabet = [
        "word ", "**bold** ", "`code` ", "[r] ", "[r][] ", "[^1] ", "\n", "\n", "\n\n", "\n\n",
        "[r]: https://e.com/r\n\n",
        "[^1]: a note\n", "===\n", "---\n", "- item\n", "- item\n\n- loose\n", "1. one\n", "> quote\n", "lazy\n",
        "```swift\nlet a = 1\nlet b = 2\nlet c = 3\nlet d = 4\n", "```\n", "~~~\nx\n", "    indented\n",
        "|a|b|\n|-|-|\n|1|2|\n",
        "e\u{301} ", "\u{301}", "界 ", "😀", "\r\n", "\r", "/tmp/x ", "<https://a.b> "
    ]

    /// The rows of a fresh transcript holding `text`, drawn as `warm` is.
    static func fresh(_ text: String, thinking: Bool, folded: Bool, columns: Int) -> [ScreenComposer.Line] {
        var transcript = transcript(folded: folded)
        if thinking { transcript.addThinkingText(text) } else { transcript.addAssistantText(text) }
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns)
    }

    static func transcript(folded: Bool) -> Transcript {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.setHighlight(true)
        transcript.setCodeFoldLines(3)
        transcript.setCodeFoldedByDefault(folded)
        return transcript
    }

    @Test func `each delta draws what a fresh layout of the text so far draws`() {
        var generator = SplitMix(seed: 0xCAC4E)
        var frames = 0
        for message in 0 ..< 120 {
            let pieces = (0 ..< 4 + Int(generator.next() % 30))
                .map { _ in
                    Self.alphabet[Int(generator.next() % UInt64(Self.alphabet.count))]
                }
            let scalars = Array(pieces.joined().unicodeScalars)
            let thinking = message % 5 == 4
            let folded = message % 2 == 0
            var warm = Self.transcript(folded: folded)
            var text = ""
            var start = 0
            while start < scalars.count {
                let end = Swift.min(scalars.count, start + 1 + Int(generator.next() % 24))
                var delta = ""
                delta.unicodeScalars.append(contentsOf: scalars[start ..< end])
                start = end
                text.unicodeScalars.append(contentsOf: delta.unicodeScalars)
                if thinking { warm.addThinkingText(delta) } else { warm.addAssistantText(delta) }
                let columns = [80, 80, 80, 31][Int(generator.next() % 4)]
                let drawn = ScreenComposer.lines(in: warm, at: 0, columns: columns)
                let expected = Self.fresh(text, thinking: thinking, folded: folded, columns: columns)
                #expect(drawn == expected, "message \(message), \(text.debugDescription)")
                if drawn != expected { return }
                frames += 1
            }
        }
        #expect(frames > 1_000)
    }

    @Test func `a block that has streamed past is not laid out again`() {
        var transcript = Self.transcript(folded: false)
        transcript.addAssistantText("First paragraph.\n\n```swift\nlet a = 1\n```\n\nThird")
        _ = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
        let before = transcript.markdownRows.blocksLaidOut
        _ = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
        #expect(transcript.markdownRows.blocksLaidOut == before)
        transcript.addAssistantText(" paragraph, longer.")
        _ = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
        #expect(transcript.markdownRows.blocksLaidOut == before + 1)
        _ = ScreenComposer.lines(in: transcript, at: 0, columns: 60)
        #expect(transcript.markdownRows.blocksLaidOut == before + 4, "a new width lays every block out")
    }

    /// A message of the same shape put where another was, as after the conversation is cleared, has the same events, ranges and all:
    /// only its bytes differ, so the rows are kept only for bytes the texts share.
    @Test func `a message put where another of the same shape was draws its own text`() {
        var transcript = Self.transcript(folded: false)
        transcript.addAssistantText("aaaa *bbbb*\n\n```swift\nlet x = 1\n```\n\ncccc")
        _ = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
        transcript.removeAll()
        transcript.addAssistantText("dddd *eeee*\n\n```swift\nvar y = 2\n```\n\nffff")
        let drawn = ScreenComposer.lines(in: transcript, at: 0, columns: 80)
        #expect(
            drawn
                == Self.fresh(
                    "dddd *eeee*\n\n```swift\nvar y = 2\n```\n\nffff", thinking: false, folded: false, columns: 80))
    }
}
