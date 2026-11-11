import Testing

@testable import AskTUI

/// A picture shows at once and folds on a click (the owner, 2026-11-06; roadmap 0208): a click on its line or its rows folds that
/// picture away, leaving its line, and a second shows it; the tool's own output fold is not touched.
@Suite("A click folds a picture away, and shows it again")
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
        transcript.startTool(name: "read", summary: "a.png", id: "r1")
        transcript.finishTool(.succeeded, output: "Read a.png", id: "r1", images: Self.pictures)
        transcript.imagePlacements[0] = Self.placements
        return transcript
    }

    private func pictureRows(_ lines: [ScreenComposer.Line]) -> [Int?] {
        lines.filter { $0.text.contains("PNG ·") || $0.text.unicodeScalars.contains { $0.value == 0x10EEEE } }
            .map(\.picture)
    }

    @Test func `a folded picture draws its line only, and each row says which picture it shows`() {
        var transcript = transcript()
        let open = ScreenComposer.lines(in: transcript, at: 0, columns: 100)
        #expect(pictureRows(open) == [0, 0, 0, 0, 1, 1, 1], "each line and its rows name their picture")
        transcript.togglePicture(0, at: 0)
        let folded = ScreenComposer.lines(in: transcript, at: 0, columns: 100)
        #expect(pictureRows(folded) == [0, 1, 1, 1], "the first picture keeps its line, the second is as it was")
        #expect(transcript.isPictureFolded(0, at: 0) && !transcript.isPictureFolded(1, at: 0))
        transcript.togglePicture(0, at: 0)
        #expect(ScreenComposer.lines(in: transcript, at: 0, columns: 100) == open)
    }

    @Test func `a click on a picture folds that picture, not the tool's output, and a second shows it`() throws {
        var rig = PointerRig(
            columns: 100,
            rows: 40,
            updates: [
                .toolStarted(name: "read", summary: "a.png", id: "r1"),
                .toolFinished(.succeeded, output: "Read a.png", id: "r1", images: Self.pictures)
            ]
        )
        rig.controller.state.transcript.imagePlacements[0] = Self.placements
        // As the screen's pictures do when they place one: a new revision, so the block is laid out again with its rows.
        rig.controller.state.transcript.revisions[0] = rig.controller.state.transcript.bump()
        rig.draw()
        let outputFolded = rig.controller.state.transcript.isFolded(0)
        let line = try #require((0 ..< 40).first { rig.text(row: $0).contains("PNG ·") })
        _ = rig.click(row: line + 1, col: 6)
        #expect(rig.controller.state.transcript.isPictureFolded(0, at: 0))
        #expect(rig.controller.state.transcript.isFolded(0) == outputFolded, "the output's fold is the tool's own")
        rig.draw()
        // Its rows gone, the line has moved: the transcript keeps its end at the bottom.
        let folded = try #require((0 ..< 40).first { rig.text(row: $0).contains("PNG ·") })
        _ = rig.click(row: folded, col: 6)
        #expect(!rig.controller.state.transcript.isPictureFolded(0, at: 0))
    }

    @Test func `a cleared conversation forgets which pictures were folded`() {
        var transcript = transcript()
        transcript.togglePicture(0, at: 0)
        transcript.removeAll()
        transcript.startTool(name: "read", summary: "a.png", id: "r1")
        transcript.finishTool(.succeeded, output: "Read a.png", id: "r1", images: Self.pictures)
        #expect(!transcript.isPictureFolded(0, at: 0))
    }
}
