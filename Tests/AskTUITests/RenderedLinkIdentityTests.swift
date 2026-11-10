internal import TerminalKitCodecs
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// n58: check the real composer, buffer and OSC 8 encoder, not only ScreenComposer.spans. Native terminal hover is not emulated.
@Suite("Rendered repeated links have separate terminal identities")
struct RenderedLinkIdentityTests {
    @Test func `repeated links in notices, Markdown and tool output get distinct OSC identities`() throws {
        let uri = "https://example.com/notes"
        let escape = "\u{1B}"
        let osc = "\(escape)]8;;\(uri)\(escape)\\site\(escape)]8;;\(escape)\\"
        for updates: [ConversationUpdate] in [
            [.notice("\(uri) and \(uri)", isError: false), .notice(uri, isError: false)],
            [.assistantText("[first](\(uri)) and [second](\(uri))\n\n[third](\(uri))")],
            [
                .toolStarted(name: "bash", summary: "links", id: "t"),
                .toolFinished(.succeeded, output: "\(osc) and \(osc)\n\(osc)", id: "t")
            ]
        ] {
            var options = ScreenOptions.legacy
            options.markdown = true
            options.foldTools = false
            var rig = PointerRig(columns: 90, rows: 24, options: options, updates: updates)
            let occurrences = cells(in: rig, uri: uri)
            #expect(occurrences.count == 3)
            let ids = try occurrences.map { try #require(rig.buffer[$0.row, $0.col].style.linkID) }
            #expect(Set(ids).count == 3)
            let bytes = String(decoding: DiffRenderer.renderFull(rig.buffer), as: UTF8.self)
            for id in ids { #expect(bytes.contains("\(escape)]8;id=\(id);\(uri)\(escape)\\")) }
            let before = rig.buffer
            let first = try #require(occurrences.first)
            rig.mouse(.release, .motion, row: first.row, col: first.col)
            let other = occurrences.dropFirst()
            for cell in other { #expect(rig.buffer[cell.row, cell.col] == before[cell.row, cell.col]) }
            rig.draw()
            #expect(cells(in: rig, uri: uri).map { rig.buffer[$0.row, $0.col].style.linkID } == ids.map(Optional.some))
        }
    }

    @Test func `repeated file paths in different blocks keep independent ids after redraw`() throws {
        var rig = PointerRig(columns: 70, rows: 16, lines: ["/tmp/a.txt and /tmp/a.txt", "/tmp/a.txt"])
        let uri = "file:///tmp/a.txt"
        let occurrences = cells(in: rig, uri: uri)
        #expect(occurrences.count == 3)
        let ids = try occurrences.map { try #require(rig.buffer[$0.row, $0.col].style.linkID) }
        #expect(Set(ids).count == 3)
        rig.draw()
        #expect(cells(in: rig, uri: uri).map { rig.buffer[$0.row, $0.col].style.linkID } == ids.map(Optional.some))
    }

    private func cells(in rig: PointerRig, uri: String) -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        for row in 0 ..< rig.buffer.rows {
            var previous: String?
            for col in 0 ..< rig.buffer.columns {
                let style = rig.buffer[row, col].style
                if style.link == uri, col == 0 || previous != style.linkID { result.append((row, col)) }
                previous = style.link == uri ? style.linkID : nil
            }
        }
        return result
    }
}
