internal import TerminalKitMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

/// Plain notices with path substitutions, not Markdown: source segments keep their original coordinates through wrapping (0215).
enum NoticePathRows {
    private struct Piece {
        var shown: String
        var original: Range<Int>
        var drawn: Range<Int>
        var linear: Bool
        var uri: String?
    }

    /// The rows of the notice `text`: as written when it names no path to show otherwise, which is every notice without a project.
    static func lines(_ text: String, isError: Bool, block: Int, width: Int, style: BlockStyle) -> [ScreenComposer.Line]
    {
        let look = isError ? Style(fg: .indexed(1)) : Style(dim: true)
        let inset = style.inset
        guard let display = style.paths, !display.paths(in: text).isEmpty else {
            let margin = String(repeating: " ", count: inset)
            return TextWrap.rows(text, width: width)
                .map { row in
                    ScreenComposer.Line(
                        text: margin + row.text,
                        style: look,
                        source: .init(block: block, line: row.line, offset: row.offset, col: inset, text: row.text)
                    )
                }
        }
        return shortened(text, block: block, width: width, inset: inset, look: look, display: display)
    }

    private static func shortened(
        _ text: String,
        block: Int,
        width: Int,
        inset: Int,
        look: Style,
        display: PathDisplay
    ) -> [ScreenComposer.Line] {
        TranscriptContent.hardLines(of: text).enumerated()
            .flatMap { number, original in
                let pieces = pieces(original, display: display)
                let shown = pieces.map(\.shown).joined()
                return TextWrap.rows(shown, width: width)
                    .map { row in
                        var line = ScreenComposer.Line(
                            text: String(repeating: " ", count: inset) + row.text,
                            style: look
                        )
                        let range = row.offset ..< row.offset + row.text.count
                        for piece in pieces where piece.drawn.overlaps(range) {
                            let low = Swift.max(range.lowerBound, piece.drawn.lowerBound)
                            let high = Swift.min(range.upperBound, piece.drawn.upperBound)
                            let part = String(piece.shown.dropFirst(low - piece.drawn.lowerBound).prefix(high - low))
                            let col =
                                inset + UnicodeWidth.displayWidth(of: String(row.text.prefix(low - range.lowerBound)))
                            let source =
                                piece.linear
                                ? piece.original.lowerBound + low - piece.drawn.lowerBound : piece.original.lowerBound
                            line.segments.append(
                                RowSegment(
                                    line: number,
                                    firstOffset: source,
                                    col: col,
                                    text: part,
                                    sourceCount: piece.linear ? high - low : piece.original.count
                                )
                            )
                            if let uri = piece.uri {
                                line.links.append(
                                    .init(columns: col ..< col + UnicodeWidth.displayWidth(of: part), carrying: uri)
                                )
                            }
                        }
                        if let first = line.segments.first {
                            line.source = ScreenComposer.Source(
                                block: block,
                                line: number,
                                offset: first.firstOffset,
                                col: first.col,
                                text: first.text
                            )
                        } else {
                            line.source = ScreenComposer.Source(
                                block: block,
                                line: number,
                                offset: 0,
                                col: inset,
                                text: ""
                            )
                        }
                        return line
                    }
            }
    }

    /// Both coordinate spaces are grapheme offsets; the path hook supplies UTF-8 ranges, converted once per path.
    private static func pieces(_ original: String, display: PathDisplay) -> [Piece] {
        let bytes = Array(original.utf8)
        let found = display.paths(in: original)
        var result: [Piece] = []
        var byte = 0
        var source = 0
        var drawn = 0
        func append(_ shown: String, originalCount: Int, linear: Bool, uri: String? = nil) {
            let count = shown.count
            result.append(
                Piece(
                    shown: shown,
                    original: source ..< source + originalCount,
                    drawn: drawn ..< drawn + count,
                    linear: linear,
                    uri: uri
                )
            )
            source += originalCount
            drawn += count
        }
        for path in found {
            let before = String(decoding: bytes[byte ..< path.bytes.lowerBound], as: UTF8.self)
            append(before, originalCount: before.count, linear: true)
            let written = String(decoding: bytes[path.bytes], as: UTF8.self)
            append(path.shown, originalCount: written.count, linear: path.shown == written, uri: path.uri)
            byte = path.bytes.upperBound
        }
        let after = String(decoding: bytes[byte...], as: UTF8.self)
        append(after, originalCount: after.count, linear: true)
        return result
    }
}
