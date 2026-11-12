import Testing

@testable import AskTUI

/// A picture block folds as every block does (the owner, 2026-11-12): to one line, its header, with the pictures' details on its
/// right. It starts open, so a picture shows at once (2026-11-06), whatever `ui.fold.tools` says: open, each picture, then its
/// details line, then the tool's output. A click on the block folds or opens it, pictures and all.
@Suite("A picture block folds to one line, and opens with its pictures then their details")
struct PictureFoldTests {
    private static let pictures = [
        ToolImage(mediaType: "image/png", data: ToolImageTests.png(100, 100)),
        ToolImage(mediaType: "image/png", data: ToolImageTests.png(50, 50))
    ]
    private static let placements = [
        ImagePlacement(id: 9, columns: 6, rows: 3), ImagePlacement(id: 10, columns: 4, rows: 2)
    ]

    private func transcript() -> Transcript {
        var transcript = Transcript()
        transcript.setToolsFoldedByDefault(true)
        transcript.startTool(name: "read", summary: "a.png", id: "r1")
        transcript.finishTool(.succeeded, output: "Read a.png", id: "r1", images: Self.pictures)
        transcript.imagePlacements[0] = Self.placements
        return transcript
    }

    private func isCell(_ line: ScreenComposer.Line) -> Bool {
        line.text.unicodeScalars.contains { $0.value == 0x10EEEE }
    }

    @Test func `it starts open, though tools fold by default: each picture, then its details, then the output`() {
        let transcript = transcript()
        #expect(!transcript.isFolded(0))
        let lines = ScreenComposer.lines(in: transcript, at: 0, columns: 100)
        let kinds =
            lines.map {
                isCell($0)
                    ? "cell" : $0.text.contains("PNG ·") ? "details" : $0.text.contains("Read a.png") ? "output" : ""
            }
            .filter { !$0.isEmpty }
        #expect(kinds == ["cell", "cell", "cell", "details", "cell", "cell", "details", "output"], "\(kinds)")
    }

    @Test func `folded, it is one line: the header, with the pictures' details on its right`() {
        var transcript = transcript()
        transcript.toggleFold(0)
        let lines = ScreenComposer.lines(in: transcript, at: 0, columns: 100)
            .filter { !$0.text.allSatisfy(\.isWhitespace) }
        #expect(lines.count == 1, "\(lines.map(\.text))")
        #expect(lines.first?.text.contains("see") == true && lines.first?.text.contains("PNG · 100×100") == true)
        #expect(lines.first?.text.contains("2 pictures") == true || lines.first?.text.contains("PNG · 100×100") == true)
    }

    @Test func `a click on the picture folds the whole block, and another opens it`() throws {
        var rig = PointerRig(
            columns: 100,
            rows: 40,
            updates: [
                .toolStarted(name: "read", summary: "a.png", id: "r1"),
                .toolFinished(.succeeded, output: "Read a.png", id: "r1", images: Self.pictures)
            ]
        )
        rig.controller.state.transcript.imagePlacements[0] = Self.placements
        rig.controller.state.transcript.revisions[0] = rig.controller.state.transcript.bump()
        rig.draw()
        #expect(!rig.controller.state.transcript.isFolded(0))
        let cell = try #require((0 ..< 40).first { rig.text(row: $0).unicodeScalars.contains { $0.value == 0x10EEEE } })
        _ = rig.click(row: cell, col: 6)
        #expect(rig.controller.state.transcript.isFolded(0))
        rig.draw()
        let header = try #require((0 ..< 40).first { rig.text(row: $0).contains("PNG ·") })
        _ = rig.click(row: header, col: 6)
        #expect(!rig.controller.state.transcript.isFolded(0))
    }

    @Test func `a read that returned a picture is shown as see, folded or open; one that did not stays read`() {
        var transcript = transcript()
        let header = { (t: Transcript, index: Int) in
            ScreenComposer.lines(in: t, at: index, columns: 100).first { !$0.text.allSatisfy(\.isWhitespace) }?.text
                ?? ""
        }
        #expect(header(transcript, 0).contains("see · a.png"), "\(header(transcript, 0))")
        transcript.toggleFold(0)
        #expect(header(transcript, 0).contains("see · a.png"), "\(header(transcript, 0))")
        transcript.startTool(name: "read", summary: "notes.txt", id: "r2")
        transcript.finishTool(.succeeded, output: "hello", id: "r2")
        #expect(header(transcript, 1).contains("read · notes.txt"), "\(header(transcript, 1))")
        guard case .tool(let name, _, _, _, _) = transcript.items[0] else { return }
        #expect(name == "read", "only the screen says see; the tool is read")
    }
}
