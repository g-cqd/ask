internal import Foundation
internal import Testing

@testable import AskTUI

/// A path's `:line` or `:line:column` reaches the click (roadmap 0216): an opener's `{line}` was always 1, because the link's address
/// leaves the place out, as the terminal needs it to.
@Suite("A clicked path carries the line and column written after it")
struct LinkLocationTests {
    private func rig(_ updates: [ConversationUpdate]) -> PointerRig {
        var options = ScreenOptions.legacy
        options.workspace = "/w/proj"
        options.home = "/Users/me"
        var rig = PointerRig(columns: 70, rows: 14, options: options)
        // Before anything is laid out: a relative path is a link only where this says the file is there.
        rig.controller.state.blocks.paths?.exists = { _ in true }
        for update in updates { rig.controller.handle(update) }
        rig.draw()
        return rig
    }

    private func click(_ needle: String, in rig: inout PointerRig) throws -> [ScreenController.Effect] {
        let row = try #require((0 ..< 14).first { rig.text(row: $0).contains(needle) })
        let text = rig.text(row: row)
        let col = text.distance(from: text.startIndex, to: try #require(text.range(of: needle)).lowerBound)
        return rig.click(row: row, col: col + 2)
    }

    @Test func `a path in a notice or a tool's output is clicked with its place`() throws {
        var rig = rig([.notice("error at /tmp/a.swift:12:5: oops, and /tmp/b.swift:7.", isError: false)])
        #expect(try click("/tmp/a.swift", in: &rig) == [.openLink("file:///tmp/a.swift#L12C5")])
        #expect(try click("/tmp/b.swift", in: &rig) == [.openLink("file:///tmp/b.swift#L7")])
    }

    @Test func `a path in a reply, shown short, is clicked with its place`() throws {
        var rig = rig([.assistantText("Fixed /w/proj/Sources/a.swift:12 and Sources/b.swift:3:9 for you.")])
        #expect(try click("Sources/a.swift", in: &rig) == [.openLink("file:///w/proj/Sources/a.swift#L12")])
        #expect(try click("Sources/b.swift", in: &rig) == [.openLink("file:///w/proj/Sources/b.swift#L3C9")])
    }

    @Test func `a path with no place, a web link and the terminal's own link are as before`() throws {
        var rig = rig([.notice("see /tmp/a.swift and https://example.com/a:12 now", isError: false)])
        #expect(try click("/tmp/a.swift", in: &rig) == [.openLink("file:///tmp/a.swift")])
        #expect(try click("https://", in: &rig) == [.openLink("https://example.com/a:12")])
        let links = PathLinks.located(PathLinks.links(in: "/tmp/a.swift:12:5", home: "/h"), in: "/tmp/a.swift:12:5")
        #expect(links.map(\.uri) == ["file:///tmp/a.swift"], "the terminal is given the address alone")
        #expect(links.map(\.line) == [12] && links.map(\.column) == [5])
    }

    @Test func `digits that are not a place are not one`() {
        for text in ["/tmp/a.swift: 12", "/tmp/a.swift:x", "/tmp/a.swift:", "/tmp/v1.2/a.swift now 12"] {
            let links = PathLinks.located(PathLinks.links(in: text, home: "/h"), in: text)
            #expect(links.allSatisfy { $0.line == nil && $0.column == nil }, "\(text)")
        }
    }
}
