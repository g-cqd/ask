import Testing

@testable import AskAgentCore

/// Found by modelling the head-and-tail cut in Lean (`development/formal/lean/OutputBuffer.lean`).
@Suite("Clipped text keeps its ends and says how much it dropped")
struct ClippedTextTests {
    @Test func `text within the limit is returned as it is`() {
        #expect(Compaction.clipped("héllo", toBytes: 6) == "héllo")
    }

    @Test func `the note counts the bytes the head and the tail do not hold`() {
        let text = String(repeating: "a", count: 100)
        let clipped = Compaction.clipped(text, toBytes: 10, note: "gone")
        #expect(clipped == "aaaaa\n[… 90 bytes gone …]\naaaaa")
    }

    @Test func `clipping valid UTF-8 text does not leave replacement characters`() {
        // Each `é` is two bytes, so a cut at ten bytes lands inside one.
        let clipped = Compaction.clipped(String(repeating: "é", count: 20), toBytes: 10)
        #expect(!clipped.contains("\u{FFFD}"))
    }

    @Test func `the note still counts every byte the head and the tail do not hold, the cut characters' included`() {
        // 40 bytes, a cut at ten: halves of five bytes cut `é` in two, so each side shows two characters (four bytes).
        let clipped = Compaction.clipped(String(repeating: "é", count: 20), toBytes: 10, note: "gone")
        #expect(clipped == "éé\n[… 32 bytes gone …]\néé")
    }

    @Test func `a limit of one byte on text that starts with a wider character shows an empty head, not a broken one`()
    {
        let clipped = Compaction.clipped("éééé", toBytes: 2, note: "gone")
        #expect(!clipped.contains("\u{FFFD}") && clipped.contains("bytes gone"))
    }
}
