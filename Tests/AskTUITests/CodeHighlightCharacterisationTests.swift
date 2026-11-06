internal import Testing

@testable import AskTUI

/// What fenced code draws as with Markdown on and highlighting off: written before highlighting existed (roadmap 0152, phase 2), so that
/// `ui.highlight` off is ask as it was, row for row. A change to the digest is a change to the off path, and must be deliberate.
@Suite("With highlighting off, fenced code draws as it did before highlighting")
struct CodeHighlightCharacterisationTests {
    static let messages = [
        "```swift\n@MainActor func f() -> Int { return 0x1F } // done\nlet s = #\"raw \"q\"\"#\n```\n",
        "```rust\n/* a\n still */ let r = r#\"x\"#;\n```\n\n```python\ndef f(a=1.5e-3): '''doc\nmore'''\n```\n",
        "```json\n{\"key\": [1, true, null, \"s\"]}\n```\n\n```html\n<a href=\"x\">&amp;</a>\n```\n",
        "```brainfuck\n++[>+<-]\n```\n\n```\nno language\n```\n\n```sh\necho \"$HOME\" # c\n```\n",
        "intro\n```lua\nlocal s = [[long\nstring]] -- c\n"
    ]

    static func digest() -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for message in messages {
            for columns in 1 ... 80 {
                for style in [BlockStyle.plain, BlockStyle()] {
                    var transcript = Transcript()
                    transcript.setMarkdown(true)
                    transcript.setCodeFoldLines(20)
                    transcript.addAssistantText(message)
                    let rendering = ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
                        .map { "\($0.text)|\($0.style)|\($0.accents)|\($0.links)" }
                        .joined(separator: "\n")
                    for byte in rendering.utf8 {
                        hash ^= UInt64(byte)
                        hash &*= 0x100_0000_01B3
                    }
                }
            }
        }
        return hash
    }

    // Moved on purpose (note n11): a single `/word` outside the root's folders is no longer linked as a path.
    @Test func `the rows of fenced code with highlighting off keep their digest`() {
        #expect(Self.digest() == 3_594_576_448_199_527_816)
    }
}
