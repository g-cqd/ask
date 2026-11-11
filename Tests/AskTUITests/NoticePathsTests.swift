internal import TerminalKitText
internal import Testing

@testable import AskTUI

@Suite("Notice paths shorten without interpreting the notice as Markdown")
struct NoticePathsTests {
    private func rig(_ text: String, shortens: Bool = true, columns: Int = 70) -> PointerRig {
        var options = ScreenOptions.legacy
        options.workspace = "/work/project"
        var rig = PointerRig(columns: columns, rows: 20, options: options)
        rig.controller.state.blocks.paths = PathDisplay(
            workspace: "/work/project",
            home: "/Users/me",
            ancestors: 2,
            shortens: shortens,
            exists: { _ in true }
        )
        rig.controller.handle(.notice(text, isError: false))
        rig.draw()
        return rig
    }

    @Test func `a notice shortens a path and keeps literal Markdown markers`() throws {
        let rig = rig("**Saved** /work/project/Sources/a.swift:12:3 now.")
        let row = try #require((0 ..< 20).first { rig.text(row: $0) == "**Saved** Sources/a.swift:12:3 now." })
        #expect(rig.controller.frame.links[row].contains { $0.uri == "file:///work/project/Sources/a.swift" })
    }

    @Test func `copying a shortened notice preserves the full source and punctuation`() throws {
        var rig = rig("Saved /work/project/Sources/a.swift now.")
        let row = try #require((0 ..< 20).first { rig.text(row: $0) == "Saved Sources/a.swift now." })
        #expect(rig.drag(from: (row, 0), to: (row, 25)).contains(.copy("Saved /work/project/Sources/a.swift now.")))
    }

    @Test func `asWritten leaves the notice text unchanged`() throws {
        let text = "Saved /work/project/Sources/a.swift now."
        let rig = rig(text, shortens: false)
        #expect((0 ..< 20).contains { rig.text(row: $0) == text })
    }

    @Test func `a wrapped shortened path retains source coordinates on every row`() {
        let text = "Saved /work/project/a_very_long_folder_name/file.swift done."
        let rig = rig(text, columns: 18)
        let rows = rig.controller.frame.rows
        let content = TranscriptContent(rig.controller.state.transcript)
        var first: Int?
        var last: Int?
        for row in 0 ..< rig.composer.transcriptRows where rows.provenance(atRow: row) != nil {
            if first == nil { first = row }
            last = row
        }
        guard let first, let last,
            let start = rows.position(row: first, col: 0),
            let end = rows.position(row: last, col: 17, edge: .trailing)
        else {
            Issue.record("notice rows were not selectable")
            return
        }
        let selected = ContentSelection(anchor: start.position, head: end.position)
        #expect(selected.text(in: content) == text)
    }
}
