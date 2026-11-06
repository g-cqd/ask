internal import TerminalKitIO
import Testing

@testable import AskTUI

/// Where pictures meet the rest of the screen (roadmap 0208, widened after the owner's doubt, 2026-11-06).
@Suite("Pictures stay with their block, fit their area, and leave with the conversation")
struct ToolImageEdgeTests {
    private static let picture = ToolImage(mediaType: "image/png", data: ToolImageTests.png(600, 300))

    private func withPicture(_ transcript: inout Transcript, id: String = "r1", images: [ToolImage] = [Self.picture]) {
        transcript.startTool(name: "read", summary: "a.png", id: id)
        transcript.finishTool(.succeeded, output: "Read a.png", id: id, images: images)
    }

    @Test func `a cleared conversation forgets its pictures, and the next block at that place has none`() {
        var transcript = Transcript()
        withPicture(&transcript)
        transcript.imagePlacements[0] = [ImagePlacement(id: 9, columns: 10, rows: 5)]
        transcript.choiceSummaryAt = 0
        transcript.removeAll()
        transcript.startTool(name: "bash", summary: "ls", id: "b1")
        transcript.finishTool(.succeeded, output: "a.png", id: "b1")
        #expect(
            transcript.toolImages.isEmpty && transcript.imagePlacements.isEmpty && transcript.choiceSummaryAt == nil
        )
        let rows = ScreenComposer.lines(in: transcript, at: 0, columns: 100, style: .plain).map(\.text)
        #expect(!rows.contains { $0.contains("PNG") }, "\(rows)")
    }

    @Test func `two pictures in one block: a line each, each followed by its own rows`() {
        var transcript = Transcript()
        withPicture(
            &transcript,
            images: [Self.picture, ToolImage(mediaType: "image/png", data: ToolImageTests.png(10, 10))]
        )
        transcript.imagePlacements[0] = [
            ImagePlacement(id: 1, columns: 4, rows: 2), ImagePlacement(id: 2, columns: 1, rows: 1)
        ]
        let rows = ScreenComposer.lines(in: transcript, at: 0, columns: 100, style: .plain).map(\.text)
        let lines = rows.indices.filter { rows[$0].contains("PNG ·") }
        #expect(lines.count == 2, "\(rows)")
        #expect(lines.count == 2 && lines[1] - lines[0] == 3, "the first picture's two rows come between: \(rows)")
    }

    @Test func `a picture is sized to the transcript's width, which the open sidebar narrows`() throws {
        var images = try #require(ScreenImages(connection: MockTerminalConnection(), mayDraw: true))
        _ = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);OK\u{1B}\\".utf8))
        var transcript = Transcript()
        withPicture(&transcript)
        let size = TerminalSize(columns: 100, rows: 60, pixelWidth: 1000, pixelHeight: 1200)
        let placed = images.place(in: &transcript, size: size, inset: 1, transcriptColumns: 60)
        #expect(placed)
        let placement = try #require(transcript.imagePlacements[0]?.first ?? nil)
        #expect(placement.columns + 2 * 1 + 4 <= 60, "\(placement)")
    }

    @Test func `a narrower transcript places a picture again, smaller, under the same id`() throws {
        var images = try #require(ScreenImages(connection: MockTerminalConnection(), mayDraw: true))
        _ = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);OK\u{1B}\\".utf8))
        var transcript = Transcript()
        withPicture(&transcript)
        let size = TerminalSize(columns: 100, rows: 60, pixelWidth: 1000, pixelHeight: 1200)
        _ = images.place(in: &transcript, size: size, inset: 1, transcriptColumns: 100)
        let wide = try #require(transcript.imagePlacements[0]?.first ?? nil)
        let refitted = images.place(in: &transcript, size: size, inset: 1, transcriptColumns: 40)
        #expect(refitted)
        let narrow = try #require(transcript.imagePlacements[0]?.first ?? nil)
        #expect(
            narrow.id == wide.id && narrow.columns < wide.columns && narrow.columns + 6 <= 40,
            "\(wide) -> \(narrow)"
        )
    }
}
