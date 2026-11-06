internal import TerminalKitIO
import Testing

@testable import AskTUI

/// The screen's pictures as pixels (roadmap 0208): nothing is placed until the terminal says it draws kitty graphics; then each PNG
/// not placed yet is placed once, sized to the terminal's cells, and recorded for the composer.
@Suite("Pictures are placed once the terminal says it draws them")
struct ScreenImagesTests {
    private func transcript() -> Transcript {
        var transcript = Transcript()
        transcript.startTool(name: "read", summary: "a.png", id: "r1")
        transcript.finishTool(
            .succeeded,
            output: "Read a.png",
            id: "r1",
            images: [ToolImage(mediaType: "image/png", data: ToolImageTests.png(100, 100))]
        )
        return transcript
    }

    private let size = TerminalSize(columns: 100, rows: 40, pixelWidth: 1000, pixelHeight: 800)

    @Test func `nothing before the answer, one placement after it, and never twice`() throws {
        var images = try #require(ScreenImages(connection: MockTerminalConnection(size: size), mayDraw: true))
        var shown = transcript()
        let early = images.place(in: &shown, size: size, inset: 1)
        #expect(!early, "not asked yet")
        let taken = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);OK\u{1B}\\".utf8))
        #expect(taken)
        let before = shown.revisions
        let placed = images.place(in: &shown, size: size, inset: 1)
        #expect(placed)
        #expect(shown.revisions != before, "the block is laid out again, with its placeholder rows")
        let index = try #require(shown.toolImages.keys.first)
        #expect(shown.imagePlacements[index] == [ImagePlacement(id: 0xA5_0001, columns: 10, rows: 5)])
        let again = images.place(in: &shown, size: size, inset: 1)
        #expect(!again, "placed once")
    }

    @Test func `a terminal that said no places nothing, and one not asked is not made`() throws {
        var images = try #require(ScreenImages(connection: MockTerminalConnection(size: size), mayDraw: true))
        var shown = transcript()
        let taken = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);ENOTSUPPORTED:no\u{1B}\\".utf8))
        #expect(taken)
        let placed = images.place(in: &shown, size: size, inset: 1)
        #expect(!placed)
        #expect(ScreenImages(connection: MockTerminalConnection(size: size), mayDraw: false) == nil)
    }
}
