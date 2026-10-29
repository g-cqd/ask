internal import Foundation
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A click on a link opens it (the terminal's own link handling cannot see clicks while ask reads the mouse): a path, a web address, an
/// email address, in any block. Anywhere else, a click does what it did.
@Suite("A click on a link opens it")
struct LinkClickTests {
    /// The row and the column a text starts at, in what the rig drew.
    private func find(_ needle: String, in rig: PointerRig) throws -> (row: Int, col: Int) {
        for row in 0 ..< rig.buffer.rows {
            let text = rig.text(row: row)
            if let range = text.range(of: needle) {
                return (row, text.distance(from: text.startIndex, to: range.lowerBound))
            }
        }
        throw LinkNotDrawn(needle: needle)
    }

    private struct LinkNotDrawn: Error { let needle: String }

    @Test func `a click on a path in a tool block opens the file, and does not fold the block`() throws {
        var rig = PointerRig(
            columns: 60,
            updates: [
                .toolStarted(name: "read", summary: "/tmp/a.swift", id: "r"),
                .toolFinished(.succeeded, output: "one\ntwo", id: "r")
            ])
        let at = try find("/tmp/a.swift", in: rig)
        let folded = rig.controller.state.transcript.isFolded(0)
        #expect(rig.click(row: at.row, col: at.col + 2) == [.openLink("file:///tmp/a.swift")])
        #expect(rig.controller.state.transcript.isFolded(0) == folded)
    }

    @Test func `a click beside the link still folds the block`() throws {
        var rig = PointerRig(
            columns: 60,
            updates: [
                .toolStarted(name: "read", summary: "/tmp/a.swift", id: "r"),
                .toolFinished(.succeeded, output: "one\ntwo", id: "r")
            ])
        let at = try find("read", in: rig)
        let folded = rig.controller.state.transcript.isFolded(0)
        #expect(!rig.click(row: at.row, col: at.col).contains { if case .openLink = $0 { true } else { false } })
        #expect(rig.controller.state.transcript.isFolded(0) != folded)
    }

    @Test func `a web address and an email address in ask's own message open too`() throws {
        var rig = PointerRig(columns: 70, lines: ["Docs: https://example.com/a?b=1 or write to me@example.com."])
        let web = try find("https://", in: rig)
        #expect(rig.click(row: web.row, col: web.col + 5) == [.openLink("https://example.com/a?b=1")])
        let mail = try find("me@example", in: rig)
        #expect(rig.click(row: mail.row, col: mail.col + 1) == [.openLink("mailto:me@example.com")])
    }

    @Test func `a double click on a link selects the word instead`() throws {
        var rig = PointerRig(columns: 70, lines: ["see https://example.com/a now"])
        let web = try find("https://", in: rig)
        _ = rig.click(row: web.row, col: web.col + 5)
        let second = rig.click(row: web.row, col: web.col + 5, after: .milliseconds(100))
        #expect(!second.contains { if case .openLink = $0 { true } else { false } })
    }
}
