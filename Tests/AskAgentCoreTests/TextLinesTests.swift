import Testing

@testable import AskAgentCore

/// The first or last line of a text without splitting all of it (note n47): a resumed session took the last line of every tool's
/// output, splitting each whole output into lines by `Character` for it. Lines are what `split(separator: "\n")` gives, a carriage
/// return before the line feed left out.
@Suite("The first and last line of a text, read from its ends")
struct TextLinesTests {
    static let texts = [
        "", "one", "one\ntwo", "one\ntwo\n", "\n\none\n\ntwo\n\n", "\n", "\n\n\n", "été\nnaïve 🙂\n", "a\n\n\nb",
        "line with trailing spaces   \n  and leading"
    ]

    @Test(arguments: texts)
    func `first and last match split's first and last`(text: String) {
        let lines = text.split(separator: "\n").map(String.init)
        #expect(TextLines.first(of: text) == lines.first)
        #expect(TextLines.last(of: text) == lines.last)
    }

    @Test func `a carriage return before the line feed is not part of the line`() {
        #expect(TextLines.first(of: "one\r\ntwo\r\n") == "one")
        #expect(TextLines.last(of: "one\r\ntwo\r\n") == "two")
    }
}
