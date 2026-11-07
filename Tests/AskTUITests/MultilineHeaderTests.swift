internal import Foundation
import TerminalKitCodecs
import TerminalKitRender
import TerminalKitStyle
import TerminalKitText
internal import Testing

@testable import AskTUI

/// Note n13: a header that takes several rows, wrapped, shimmers and brightens as one, and in the padded look the hover lights the
/// header, not the blank padding row above it.
@Suite("A header over several rows shimmers and brightens as one")
struct MultilineHeaderTests {
    private static let long = String(repeating: "longpath/", count: 12) + "a.swift"

    private func running(after elapsed: Duration) -> Transcript {
        var transcript = Transcript()
        transcript.startTool(name: "read", summary: Self.long, id: "r")
        transcript.toggleFold(0)
        if let started = transcript.progress[0]?.started {
            transcript.progress[0]?.sampled = started.advanced(by: elapsed)
        }
        return transcript
    }

    private func headerRows(_ transcript: Transcript) -> [ScreenComposer.Line] {
        ScreenComposer.lines(in: transcript, at: 0, columns: 50, style: BlockStyle()).filter { $0.source?.line == 0 }
    }

    @Test func `the shimmer goes on along every row of a wrapped header`() throws {
        let rows = headerRows(running(after: .zero))
        try #require(rows.count >= 2, "the header wraps: \(rows.map(\.text))")
        let first = UnicodeWidth.displayWidth(of: try #require(rows[0].source).text)
        // Far enough in to have left the first row.
        let into = Duration.milliseconds(
            (first + ScreenComposer.shimmerWidth + 3) * 1_000 / ScreenComposer.shimmerSpeed
        )
        let later = headerRows(running(after: into))
        #expect(later[0].accents.isEmpty && !later[1].accents.isEmpty, "\(later.map(\.accents))")
        #expect(later.allSatisfy { $0.style.fg == BlockStyle().theme.shimmerBase }, "every row of it faint")
    }

    private func rig(columns: Int = 50) -> PointerRig {
        var options = ScreenOptions()
        options.hover = true
        let rig = PointerRig(
            columns: columns,
            rows: 20,
            options: options,
            updates: [
                .toolStarted(name: "read", summary: Self.long, id: "r"),
                .toolFinished(.succeeded, output: "one\ntwo", id: "r")
            ]
        )
        return rig
    }

    private func bold(_ rig: PointerRig, row: Int) -> Bool {
        (0 ..< rig.buffer.columns).contains { rig.buffer[row, $0].character != " " && rig.buffer[row, $0].style.bold }
    }

    @Test func `in the padded look the hover lights the header, every row of it`() throws {
        var rig = rig()
        rig.controller.state.transcript.toggleFold(0)
        rig.draw()
        let rows = (0 ..< rig.buffer.rows).filter { rig.text(row: $0).contains("longpath") }
        try #require(rows.count >= 2, "\((0 ..< rig.buffer.rows).map { rig.text(row: $0) })")
        rig.mouse(.release, .motion, row: rows[0], col: 3)
        rig.draw()
        #expect(rows.allSatisfy { bold(rig, row: $0) }, "\(rows)")
        let output = try #require((0 ..< rig.buffer.rows).first { rig.text(row: $0).contains("one") })
        #expect(!bold(rig, row: output), "the output is not the header")
    }

    @Test func `the pointer is a hand over what a click acts on, and the arrow elsewhere`() throws {
        var rig = PointerRig(columns: 60, rows: 14, options: ScreenOptions(), lines: ["see https://example.com/a now"])
        rig.controller.handle(.toolStarted(name: "bash", summary: "make", id: "t", command: ToolCommand()))
        rig.controller.handle(.toolFinished(.succeeded, output: "ok", id: "t"))
        rig.draw()
        let link = try #require((0 ..< rig.buffer.rows).first { rig.text(row: $0).contains("https://") })
        let col = try #require(
            rig.text(row: link).range(of: "https://")
                .map { rig.text(row: link).distance(from: rig.text(row: link).startIndex, to: $0.lowerBound) }
        )
        rig.mouse(.release, .motion, row: link, col: col + 3)
        #expect(rig.controller.state.pointer == .pointer)
        rig.mouse(.release, .motion, row: link, col: col - 3)
        #expect(rig.controller.state.pointer == .default, "beside the link, in a notice that folds nothing")
        let block = try #require((0 ..< rig.buffer.rows).first { rig.text(row: $0).contains("bash") })
        rig.mouse(.release, .motion, row: block, col: 2)
        #expect(rig.controller.state.pointer == .pointer)
    }

    @Test func `the shapes are sent as OSC 22`() {
        #expect(PointerShape.pointer.sequence == Array("\u{1B}]22;pointer\u{1B}\\".utf8))
        #expect(PointerShape.default.sequence == Array("\u{1B}]22;default\u{1B}\\".utf8))
    }
}
