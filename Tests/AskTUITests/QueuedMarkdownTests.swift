import Testing

@testable import AskTUI

/// A queued message (note n43) is drawn as Markdown, as the person's sent messages are: its marks become styles, under the dim look
/// and the `<spinner> · ` lead, with the other rows hanging under it.
@Suite("A queued message is drawn as Markdown")
struct QueuedMarkdownTests {
    private func rows(_ text: String, markdown: Bool = true) -> [String] {
        var transcript = MarkdownRowCacheTests.transcript(folded: false)
        transcript.markdown = markdown
        transcript.addQueued(text)
        return ScreenComposer.lines(in: transcript, at: 0, columns: 60).map(\.text)
            .filter { !$0.allSatisfy(\.isWhitespace) }
    }

    @Test func `its marks are styles, under the lead, and the next rows hang under it`() throws {
        let shown = rows("**bold** and `code`\n\n- one\n- two")
        let first = try #require(shown.first)
        #expect(first.contains(" · bold and code") && !first.contains("**") && !first.contains("`"))
        #expect(shown.contains { $0.contains("one") && !$0.contains(" · ") }, "the list hangs under the lead")
    }

    @Test func `with Markdown off it is the text as written`() {
        #expect(rows("**bold**", markdown: false).first?.contains("**bold**") == true)
    }
}
