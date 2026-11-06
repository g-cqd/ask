internal import TerminalKitCodecs
internal import TerminalKitStyle

/// The rows that say a tool's pictures, right under its header (roadmap 0208): what each is, its pixel size and its byte size,
/// whether the output is folded or not (the owner, 2026-11-06: shown at once). Where the terminal draws pixels, the picture will
/// take rows here too; elsewhere this row is all there is.
extension ScreenComposer {
    static func withImageRows(
        _ lines: [Line],
        images: [ToolImage],
        placements: [ImagePlacement?] = [],
        block: Int,
        inset: Int
    ) -> [Line] {
        guard !images.isEmpty, let header = lines.first else { return lines }
        let margin = String(repeating: " ", count: inset + 2)
        let source = Source(block: block, line: 0, offset: 0, col: inset, text: "")
        var rows: [Line] = []
        for (index, image) in images.enumerated() {
            rows.append(Line(text: margin + caption(image), style: Style(dim: true), source: source))
            if index < placements.count, let placement = placements[index] {
                rows += pictureRows(placement, margin: margin, source: source)
            }
        }
        return [header] + rows + lines.dropFirst()
    }

    /// The placeholder cells that draw `placement`, a row per cell row, in the colour that names its image.
    private static func pictureRows(_ placement: ImagePlacement, margin: String, source: Source) -> [Line] {
        let color = KittyPlaceholder.color(for: placement.id)
        let style = Style(fg: .rgb(r: color.red, g: color.green, b: color.blue))
        return (0 ..< placement.rows)
            .map { row in
                let cells = (0 ..< placement.columns).compactMap { KittyPlaceholder.cell(row: row, column: $0) }
                    .joined()
                return Line(text: margin + cells, style: style, source: source)
            }
    }

    /// `PNG · 1280×800 · 245 KB`.
    static func caption(_ image: ToolImage) -> String {
        let kind = image.mediaType.split(separator: "/").last.map { $0.uppercased() } ?? image.mediaType
        let size = image.pixelSize.map { "\($0.width)×\($0.height)" }
        return ([kind] + [size].compactMap(\.self) + [bytes(image.data.count)]).joined(separator: " · ")
    }

    /// A byte count as it is read: `29 B`, `245 KB`, `3.1 MB`.
    private static func bytes(_ count: Int) -> String {
        if count < 1_024 { return "\(count) B" }
        if count < 1_024 * 1_024 { return "\(count / 1_024) KB" }
        let tenths = count * 10 / (1_024 * 1_024)
        return "\(tenths / 10).\(tenths % 10) MB"
    }
}
