internal import Testing

@testable import AskTUI

/// Paths in replies on the screen (roadmap 0215): shown relative to the project and linked, the person's own message left as written,
/// and a copy of a shortened path taking the full path the model wrote.
@Suite("A reply's paths are shown short, linked, and copied in full")
struct ReplyPathsTests {
    private static let full = "/w/proj/Sources/a.swift"

    private func rig(_ updates: [ConversationUpdate], short: Bool = true) -> PointerRig {
        var options = ScreenOptions(tint: false, separator: false, padding: false)
        options.workspace = "/w/proj"
        options.home = "/Users/me"
        options.shortPaths = short
        return PointerRig(columns: 60, rows: 12, options: options, updates: updates)
    }

    private func row(_ rig: PointerRig, containing text: String) -> Int? {
        (0 ..< 12).first { rig.text(row: $0).contains(text) }
    }

    @Test func `a reply shows the path relative to the project, and links it to the file`() throws {
        let rig = rig([.assistantText("Fixed \(Self.full):12 for you.")])
        let row = try #require(row(rig, containing: "Fixed Sources/a.swift:12 for you."))
        let shown = try #require(
            rig.controller.frame.links.indices.contains(row) ? rig.controller.frame.links[row] : nil
        )
        #expect(shown.contains { $0.uri == "file://" + Self.full })
    }

    @Test func `a path with underscores, which Markdown splits its text at, is shown short too`() {
        let rig = rig([.assistantText("See /w/proj/my_dir/a_b.swift here.")])
        #expect(row(rig, containing: "See my_dir/a_b.swift here.") != nil)
    }

    @Test func `the person's own message keeps the path as written`() {
        let rig = rig([.userPrompt("look at \(Self.full)")])
        #expect(row(rig, containing: "look at \(Self.full)") != nil)
    }

    @Test func `a copy of the shortened path takes the full path`() throws {
        var rig = rig([.assistantText("Fixed \(Self.full) now.")])
        let row = try #require(row(rig, containing: "Fixed Sources/a.swift now."))
        let start = try #require(rig.text(row: row).firstRange(of: "Fixed")).lowerBound
            .utf16Offset(in: rig.text(row: row))
        let effects = rig.drag(from: (row, start), to: (row, start + 25))
        #expect(effects.contains(.copy("Fixed \(Self.full) now.")), "\(effects)")
    }

    @Test func `with ui.paths asWritten the path is shown as written`() {
        let rig = rig([.assistantText("Fixed \(Self.full) now.")], short: false)
        #expect(row(rig, containing: "Fixed \(Self.full) now.") != nil)
    }
}
