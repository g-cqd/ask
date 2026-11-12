internal import TerminalKitIO
import Testing

@testable import AskTUI

/// Pictures sent while they are laid out (roadmap 0208): every picture is placed, so its rows are kept and nothing moves as the
/// view scrolls, but only those near what is shown are sent to the terminal; one far from it is deleted there, its data freed, and
/// sent again when the view comes back to it.
@Suite("Only the pictures near the view are in the terminal")
struct ScreenImagesWindowTests {
    private let size = TerminalSize(columns: 100, rows: 40, pixelWidth: 1000, pixelHeight: 800)

    /// Sixty blocks, a picture in the first and the last.
    private func transcript() -> Transcript {
        var transcript = Transcript()
        for index in 0 ..< 60 {
            if index == 0 || index == 59 {
                transcript.startTool(name: "read", summary: "a.png", id: "r\(index)")
                transcript.finishTool(
                    .succeeded,
                    output: "Read a.png",
                    id: "r\(index)",
                    images: [ToolImage(mediaType: "image/png", data: ToolImageTests.png(100, 100))]
                )
            } else {
                transcript.addNotice("block \(index)", isError: false)
            }
        }
        return transcript
    }

    private func ids(_ transcript: Transcript) throws -> (first: UInt32, last: UInt32) {
        (
            try #require(transcript.imagePlacements[0]?.first ?? nil).id,
            try #require(transcript.imagePlacements[59]?.first ?? nil).id
        )
    }

    @Test func `all are placed, but only those near the view are sent; far ones are deleted, and sent again on return`()
        throws
    {
        var images = try #require(ScreenImages(connection: MockTerminalConnection(size: size), mayDraw: true))
        _ = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);OK\u{1B}\\".utf8))
        var shown = transcript()
        _ = images.place(in: &shown, size: size, inset: 1, near: 50 ... 59)
        let (first, last) = try ids(shown)
        #expect(images.sent == [last], "the first picture keeps its rows but is not sent yet")
        _ = images.place(in: &shown, size: size, inset: 1, near: 0 ... 9)
        #expect(images.sent == [first], "the last, fifty blocks away, is deleted from the terminal")
        _ = images.place(in: &shown, size: size, inset: 1, near: 30 ... 39)
        #expect(
            images.sent == [first],
            "within forty blocks a sent picture stays: scrolling back and forth sends nothing"
        )
        _ = images.place(in: &shown, size: size, inset: 1)
        #expect(images.sent == [first, last], "with no view known, everything is near")
        #expect(try ids(shown) == (first, last), "each keeps its id throughout")
    }
}
