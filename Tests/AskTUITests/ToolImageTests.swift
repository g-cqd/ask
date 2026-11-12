import Testing

@testable import AskTUI

/// A tool's pictures on the screen (roadmap 0208), first as a row each under the tool's header: what it is, its pixel size and its
/// byte size, shown whether the output is folded or not. A terminal that draws pixels will draw the picture there too.
@Suite("A tool's pictures show under its header")
struct ToolImageTests {
    /// The smallest headers that say a size: a PNG's IHDR, a GIF's screen, a JPEG's SOF0, a WebP's VP8X.
    static func png(_ width: Int, _ height: Int) -> [UInt8] {
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
            + bigEndian(width) + bigEndian(height) + [8, 6, 0, 0, 0]
    }

    static func bigEndian(_ value: Int) -> [UInt8] { (0 ..< 4).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) } }

    static let gif: [UInt8] = Array("GIF89a".utf8) + [0x40, 0x01, 0xF0, 0x00]  // 320×240
    static let jpeg: [UInt8] = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0xE0, 0x02, 0x80
    ]  // 640×480
    static let webp: [UInt8] =
        Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBPVP8X".utf8) + [10, 0, 0, 0, 0, 0, 0, 0] + [
            0x7F, 0x07, 0x00, 0x37, 0x04, 0x00
        ]  // 1920×1080

    @Test func `the pixel size is read from each kind's header`() {
        #expect(ImagePixelSize.read(Self.png(1280, 800)).map { [$0.width, $0.height] } == [1280, 800])
        #expect(ImagePixelSize.read(Self.gif).map { [$0.width, $0.height] } == [320, 240])
        #expect(ImagePixelSize.read(Self.jpeg).map { [$0.width, $0.height] } == [640, 480])
        #expect(ImagePixelSize.read(Self.webp).map { [$0.width, $0.height] } == [1920, 1080])
        #expect(ImagePixelSize.read(Array("not an image".utf8)) == nil)
        #expect(ImagePixelSize.read([0x89, 0x50]) == nil, "a cut header says nothing")
    }

    private func screen(folded: Bool) -> ScreenController {
        var screen = ScreenController(label: "m", options: ScreenOptions(prompt: "ask> "))
        screen.setScreenRows(30)
        _ = screen.handle(
            .toolStarted(name: "read", summary: "shot.png", id: "r1", fullInput: "{\"path\":\"shot.png\"}")
        )
        _ = screen.handle(
            .toolFinished(
                .succeeded,
                output: "Read shot.png",
                id: "r1",
                images: [ToolImage(mediaType: "image/png", data: Self.png(1280, 800))]
            )
        )
        if let index = screen.state.transcript.items.indices.last, screen.state.transcript.isFolded(index) != folded {
            _ = screen.state.transcript.toggleFold(index)
        }
        return screen
    }

    private func rows(_ screen: ScreenController, folded shownFolded: Bool) -> [String] {
        let transcript = screen.state.transcript
        guard let index = transcript.items.indices.last else { return [] }
        #expect(transcript.isFolded(index) == shownFolded)
        return ScreenComposer.lines(in: transcript, at: index, columns: 100, style: .plain)
            .map { $0.text.trimmingTrailingSpaces }
    }

    @Test func `open, the picture's details follow the header; folded, they are on the header's one line`() {
        let open = rows(screen(folded: false), folded: false)
        #expect(open.count >= 2 && open.dropFirst().first?.contains("PNG · 1280×800 · 29 B") == true, "\(open)")
        let folded = rows(screen(folded: true), folded: true).filter { !$0.allSatisfy(\.isWhitespace) }
        #expect(folded.count == 1 && folded.first?.contains("PNG · 1280×800 · 29 B") == true, "\(folded)")
    }
}

extension String {
    fileprivate var trimmingTrailingSpaces: String {
        var text = self
        while text.last == " " { text.removeLast() }
        return text
    }
}
