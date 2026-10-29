internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// Each occurrence of a link is its own link to the terminal (OSC 8 `id`), so hovering one path does not light up every other copy of it.
@Suite("Every link on screen is its own")
struct LinkIdentityTests {
    @Test func `two occurrences of one path get different ids, and one occurrence keeps its id across frames`() {
        var line = ScreenComposer.Line(text: "/tmp/a and /tmp/a", style: .default)
        line.links = PathLinks.links(in: line.text, home: "/Users/x")
        #expect(line.links.count == 2 && line.links[0].uri == line.links[1].uri)
        let linked = ScreenComposer.spans(of: line, highlight: nil, row: 7).map(\.1).filter { $0.link != nil }
        let ids = linked.compactMap(\.linkID)
        #expect(ids.count == 2 && Set(ids).count == 2)
        #expect(ids.allSatisfy(Style.isSafeLinkID))
        let again = ScreenComposer.spans(of: line, highlight: nil, row: 7).map(\.1).compactMap(\.linkID)
        #expect(again == ids)
        let elsewhere = ScreenComposer.spans(of: line, highlight: nil, row: 8).map(\.1).compactMap(\.linkID)
        #expect(Set(elsewhere).isDisjoint(with: ids), "the same text on another row is other links")
    }
}
