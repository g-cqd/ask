internal import Testing

@testable import AskTUI

/// Splitting a text into lines by its bytes gives the lines a split by characters gives (roadmap 0152): a line feed is a character
/// of its own except right after a carriage return, where the two are one, and the character split does not cut there.
struct LineSplitTests {
    static let tricky = [
        "", "\n", "\n\n", "a", "a\n", "\na", "a\nb", "a\r\nb", "\r\n", "\r\n\r\n", "\r", "a\rb", "\n\r", "\n\u{301}",
        "x\n\u{301}y", "界\n😀", "\r\r\n\n", "```swift\nlet a = 1\n```"
    ]
    static let alphabet = ["a", " ", "`", "~", "\n", "\n", "\r", "\r\n", "\u{301}", "é", "界", "😀", "\u{200D}"]

    static func texts() -> [String] {
        var generator = SplitMix(seed: 0x11E5)
        var texts = tricky
        for _ in 0 ..< 5_000 {
            let count = Int(generator.next() % 20)
            texts.append((0 ..< count).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] }.joined())
        }
        return texts
    }

    @Test func `a text's lines by bytes are its lines by characters`() {
        for text in Self.texts() {
            let expected = text.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(LineSplit.lines(of: text) == expected, "\(text.unicodeScalars.map(\.value))")
        }
    }
}
