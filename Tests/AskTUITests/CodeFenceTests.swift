internal import Testing

@testable import AskTUI

/// Fenced code is found the way CommonMark finds it, and a long block is replaced by one placeholder line only when folded.
@Suite("Code fences are found by line, and a long one folds to a placeholder")
struct CodeFenceTests {
    private func scan(_ text: String) -> [CodeFence] {
        CodeFence.scan(text.split(separator: "\n", omittingEmptySubsequences: false))
    }

    @Test func `backticks and tildes open and close their own kind`() {
        #expect(
            scan("a\n```swift  \nx\n```\nb\n~~~\ny\n~~~~")
                == [
                    CodeFence(openingLine: 1, lastLine: 3, language: "swift", isClosed: true),
                    CodeFence(openingLine: 5, lastLine: 7, language: "", isClosed: true)
                ])
        // A tilde line does not close a backtick block, a shorter fence does not close a longer one, and a fence with text after it
        // is content.
        #expect(scan("````\n~~~\n```\n```` x\n````").map(\.lastLine) == [4])
        #expect(scan("```\n~~~\nx\n```").map(\.lastLine) == [3], "a tilde fence is content inside a backtick block")
    }

    @Test func `indentation, short markers and backticks in the info string are not fences`() {
        #expect(scan("    ```\nx\n    ```").isEmpty)
        #expect(scan("``\nx\n``").isEmpty)
        #expect(scan("```a`b\nx").isEmpty)
        #expect(scan("   ```go\nx\n   ```") == [CodeFence(openingLine: 0, lastLine: 2, language: "go", isClosed: true)])
    }

    @Test func `an unclosed block runs to the end and counts what it holds so far`() {
        let fence = scan("say\n```py\na\nb")
        #expect(fence == [CodeFence(openingLine: 1, lastLine: 3, language: "py", isClosed: false)])
        #expect(fence.first?.bodyLines == 2)
        #expect(scan("```").first?.bodyLines == 0)
    }

    @Test func `only a block longer than the limit folds, to a line that says its language and length`() {
        let text = "intro\n```swift\na\nb\nc\nd\n```\nmid\n```\nshort\n```\nend"
        let folded = ShownCode(text, longerThan: 3) { _ in true }
        #expect(folded.text == "intro\ncode · swift · 4 lines\nmid\n```\nshort\n```\nend")
        #expect(folded.toggles == [1: 0] && folded.placeholders == [1])
        let open = ShownCode(text, longerThan: 3) { _ in false }
        #expect(open.text == text && open.toggles == [1: 0] && open.placeholders.isEmpty)
        #expect(ShownCode(text, longerThan: 4) { _ in true }.text == text)
    }

    @Test func `the quick look for a fence marker misses none, and agrees with a plain search`() {
        for (text, expected) in [
            ("", false), ("``", false), ("~~\n~", false), ("`~`~`~", false), ("a ``` b", true), ("x~~~", true),
            ("``\n`", false), ("``` ~~~", true), ("ab`\n``", false), ("日本```", true)
        ] { #expect(ShownCode.mayContainFence(text) == expected, "\(text.debugDescription)") }
        var generator = SystemRandomNumberGenerator()
        let pieces = ["`", "~", "a", "\n", " ", "日"]
        for _ in 0 ..< 1_000 {
            let text = (0 ..< Int.random(in: 0 ... 12, using: &generator))
                .map { _ in pieces.randomElement(using: &generator)! }
                .joined()
            let maybe = ShownCode.mayContainFence(text)
            #expect(maybe || scan(text).isEmpty, "a fence the quick look missed: \(text.debugDescription)")
            #expect(maybe == (text.contains("```") || text.contains("~~~")), "\(text.debugDescription)")
        }
    }

    @Test func `each long block keeps its own ordinal and its own state`() {
        let block = "```\n1\n2\n3\n```"
        let shown = ShownCode([block, "x", block].joined(separator: "\n"), longerThan: 2) { $0 == 1 }
        #expect(shown.text == "```\n1\n2\n3\n```\nx\ncode · 3 lines")
        #expect(shown.toggles == [0: 0, 6: 1] && shown.placeholders == [6])
    }

    /// Any text, any fold choices: opening every block shows the source, and folding takes exactly the folded blocks' extra lines.
    @Test func `generated messages keep every line that is not folded`() {
        var generator = SystemRandomNumberGenerator()
        let pieces = ["text", "```", "```swift", "~~~", "````", "    ```", "", "a ``` b", "~~~~ x"]
        for _ in 0 ..< 500 {
            let lines = (0 ..< Int.random(in: 0 ... 30, using: &generator))
                .map { _ in
                    pieces.randomElement(using: &generator)!
                }
            let text = lines.joined(separator: "\n")
            let limit = Int.random(in: 0 ... 4, using: &generator)
            let choice = (0 ..< 32).map { _ in Bool.random(using: &generator) }
            #expect(ShownCode(text, longerThan: limit) { _ in false }.text == text)
            let shown = ShownCode(text, longerThan: limit) { choice[$0] }
            let fences = CodeFence.scan(text.split(separator: "\n", omittingEmptySubsequences: false))
            let removed = fences.enumerated().filter { $0.element.bodyLines > limit && choice[$0.offset] }
                .map { $0.element.lastLine - $0.element.openingLine }.reduce(0, +)
            let count = { (string: String) in string.split(separator: "\n", omittingEmptySubsequences: false).count }
            #expect(count(shown.text) == count(text) - removed, "\(text.debugDescription) limit \(limit)")
        }
    }
}
