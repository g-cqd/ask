import TerminalKitCodecs
import Testing

@testable import AskTUI

/// A picture placed as pixels (roadmap 0208): sized in cells, never past its own pixels, the transcript's width or the row cap, its
/// shape kept; sent once and placed virtually, so the rows of placeholder cells under its line draw it.
@Suite("A picture is sized in cells, sent once, and drawn by its placeholder rows")
struct ImagePlacementTests {
    @Test func `sized to its pixels, capped by width and rows, its shape kept`() {
        let cell = (width: 10, height: 20)
        // 100×100 pixels in 10×20 cells: 10 columns, 5 rows; never larger than that.
        #expect(Self.fit((100, 100), cell, 80, 30) == [10, 5])
        // 2000×1000 in a 50-column transcript: 50 columns, 13 rows (2000/10 = 200 columns would not fit).
        #expect(Self.fit((2000, 1000), cell, 50, 30) == [50, 13])
        // A tall one held to 6 rows: 6 rows, its width cut to keep the shape.
        #expect(Self.fit((400, 4000), cell, 80, 6) == [2, 6])
        #expect(Self.fit((1, 1), cell, 80, 30) == [1, 1], "at least one cell")
    }

    private static func fit(_ pixels: (Int, Int), _ cell: (width: Int, height: Int), _ columns: Int, _ rows: Int)
        -> [Int]
    {
        let fit = ImagePlacement.fit(pixels: pixels, cell: cell, maxColumns: columns, maxRows: rows)
        return [fit.columns, fit.rows]
    }

    @Test func `it is sent once as PNG, quietly, then placed virtually over its cells`() {
        let text = String(
            decoding: ImagePlacement.commands(id: 42, png: [1, 2, 3], columns: 10, rows: 5),
            as: UTF8.self
        )
        #expect(
            text.contains("a=t") && text.contains("f=100") && text.contains("i=42") && text.contains("q=2"),
            "\(text)"
        )
        #expect(
            text.contains("a=p") && text.contains("U=1") && text.contains("c=10") && text.contains("r=5"),
            "\(text)"
        )
    }

    @Test func `its rows follow its line: placeholder cells in its colour, one row per cell row`() {
        let image = ToolImage(mediaType: "image/png", data: ToolImageTests.png(100, 100))
        let header = ScreenComposer.Line(text: "read · a.png", style: .default)
        let rows = ScreenComposer.withImageRows(
            [header],
            images: [image],
            placements: [ImagePlacement(id: 42, columns: 10, rows: 5)],
            block: 0,
            inset: 0
        )
        #expect(rows.count == 1 + 1 + 5, "header, line, five rows")
        let first = rows[2]
        #expect(first.text.filter { $0.unicodeScalars.first == KittyPlaceholder.character }.count == 10)
        let color = KittyPlaceholder.color(for: 42)
        #expect(first.style.fg == .rgb(r: color.red, g: color.green, b: color.blue))
        #expect(rows[6].text.contains(KittyPlaceholder.cell(row: 4, column: 9)!))
    }
}
