internal import Testing

@testable import AskTUI

/// What long fenced blocks draw as with Markdown on, folded and open, pinned before a folded block stopped being laid out only to be
/// dropped (roadmap 0152): the fence is found from the block's source instead of its first row, and must be the same fence.
@Suite("Long code blocks fold and open as they did before the folded ones were skipped")
struct CodeFoldCharacterisationTests {
    static func long(_ count: Int, _ line: (Int) -> String) -> String {
        (0 ..< count).map(line).joined(separator: "\n")
    }

    static let messages = [
        "intro\n\n```swift\n" + long(6) { "let v\($0) = \($0) // c" } + "\n```\n\nafter",
        "~~~\n" + long(6) { "plain \($0)" } + "\n~~~\n\n```js\n" + long(7) { "f(\($0));" } + "\n```\n",
        "streaming\n```rust\n" + long(8) { "let r\($0) = r#\"x\"#;" },
        "- item\n\n  ```sh\n" + long(6) { "  echo \($0)" } + "\n  ```\n",
        "para\n\n" + long(6) { "    indented \($0)" } + "\n\nend",
        "```swift\n" + long(3) { "short \($0)" } + "\n```\n"
    ]

    static func digest() -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for message in messages {
            for columns in 1 ... 80 {
                for highlight in [false, true] {
                    for folded in [true, false] {
                        var transcript = Transcript()
                        transcript.setMarkdown(true)
                        transcript.setHighlight(highlight)
                        transcript.setCodeFoldLines(3)
                        transcript.setCodeFoldedByDefault(folded)
                        transcript.addAssistantText(message)
                        let rendering =
                            ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: BlockStyle())
                            .map { "\($0.text)|\($0.style)|\($0.accents)|\($0.links)|\(String(describing: $0.source))" }
                            .joined(separator: "\n")
                        for byte in rendering.utf8 {
                            hash ^= UInt64(byte)
                            hash &*= 0x100_0000_01B3
                        }
                    }
                }
            }
        }
        return hash
    }

    @Test func `the rows of long blocks, folded and open, keep their digest`() {
        #expect(Self.digest() == 5_813_088_651_392_062_619)
    }

    @Test func `the long blocks of these messages do fold`() {
        for (index, message) in Self.messages.prefix(3).enumerated() {
            let rows = Self.rows(message)
            #expect(rows[0] < rows[1], "message \(index): \(rows)")
        }
    }

    /// It did not: its first row, the blank line's, names no source, so the fence was looked for a line too low.
    @Test func `a long block whose first line is blank folds`() {
        let rows = Self.rows("```python\n\n" + Self.long(5) { "x\($0) = '/tmp/\($0)'" } + "\n```\n")
        #expect(rows[0] < rows[1], "\(rows)")
    }

    /// The rows a message takes at 80 columns, folded and open.
    static func rows(_ message: String) -> [Int] {
        [true, false]
            .map { folded in
                var transcript = Transcript()
                transcript.setMarkdown(true)
                transcript.setCodeFoldLines(3)
                transcript.setCodeFoldedByDefault(folded)
                transcript.addAssistantText(message)
                return ScreenComposer.lines(in: transcript, at: 0, columns: 80).count
            }
    }
}
