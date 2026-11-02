internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// A `~/` path in any block links under the home ask was started with, as the transcript's Markdown links do, not the account's own home:
/// the screen follows `HOME` (``ScreenOptions/home``), and a characterisation pins rows on any machine.
@Suite("Paths under ~ in blocks link under the screen's home")
struct BlockHomeLinkTests {
    @Test func `a block's ~/ path links under the style's home`() {
        var style = BlockStyle()
        style.home = "/Users/someone"
        let rows = ScreenComposer.framed(
            [ScreenComposer.Line(text: "see ~/notes/a.md", style: .default)],
            kind: .notice("", isError: false),
            style: style,
            spacerAbove: false
        )
        #expect(rows.flatMap(\.links).map(\.uri) == ["file:///Users/someone/notes/a.md"])
    }

    @Test func `the screen's options set the blocks' home`() {
        var options = ScreenOptions()
        options.home = "/Users/someone"
        let state = ScreenState(label: "ask", options: options)
        #expect(state.blocks.home == "/Users/someone")
    }
}
