internal import Testing

@testable import AskTUI

/// What rendered Markdown rows become as transcript rows, pinned before their conversion stopped measuring each merged segment again
/// for every run (roadmap 0152): text, accents, links and the source segments a selection maps through. Seeded random messages mix
/// marks, code, links and characters that join their neighbours.
@Suite("Markdown rows convert as they did before")
struct MarkdownRowCharacterisationTests {
    static let alphabet = [
        "a", "b", " ", " ", "*", "_", "`", "**", "[x](https://e.com)", "<https://a.b>", "&amp;", "\t", "\n", "\n\n",
        "# ", "- ",
        "> ", "e\u{301}", "\u{301}", "界", "😀", "👍🏽", "~/p", " /tmp/x ", "1. ", "\\*",
        "```swift\nlet a = \"é\" // c\n```\n"
    ]

    static func messages() -> [String] {
        var generator = SplitMix(seed: 0x0152)
        return (0 ..< 400)
            .map { _ in
                (0 ..< Int(generator.next() % 40)).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] }
                    .joined()
            }
    }

    /// The home `~` stands for, the same on every machine (CI's is `/Users/runner`).
    static let home = "/Users/ask"

    static var style: BlockStyle {
        var style = BlockStyle()
        style.home = home
        return style
    }

    static func digest(_ messages: [String] = messages()) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for message in messages {
            for columns in [7, 23, 80] {
                for highlight in [false, true] {
                    var transcript = Transcript()
                    transcript.home = Self.home
                    transcript.setMarkdown(true)
                    transcript.setHighlight(highlight)
                    transcript.addAssistantText(message)
                    let rendering = ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
                        .map { "\($0.text)|\($0.accents)|\($0.links)|\($0.segments)|\(String(describing: $0.source))" }
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
    @Test func `the rows of random Markdown keep their digest`() {
        #expect(Self.digest() == 15_554_548_159_868_817_949)
    }
}
