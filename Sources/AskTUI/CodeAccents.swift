internal import AemiLexers
internal import TerminalKitStyle
internal import TerminalKitText

/// A file's text lexed line by line, and the colours of its tokens placed on the rows `TextWrap` cuts it into (roadmap 0152, phase 3).
/// The text is lexed as the wrap measures it, tabs as four spaces, so a token's bytes are the row's; each row then finds its bytes from
/// its grapheme offset, walking on from where the row before it stopped, so a long line cut into many rows is walked once.
struct CodeAccents {
    /// Each hard line as the wrap sees it, and its tokens' byte ranges with their colours.
    private var lines: [(text: Substring, ascii: Bool, tokens: [(bytes: Range<Int>, style: Style)])] = []
    /// Where the last row ended: its hard line, grapheme offset, and byte offset in that line.
    private var cursor = (line: -1, offset: 0, byte: 0)

    init(_ text: String, code: FileCode) {
        let wrapped = text.utf8.contains(0x09) ? text.replacing("\t", with: "    ") : text
        let lexer = LexicalLineLexer(language: code.language)
        var sides = LexSides()
        var tokens: [LineToken] = []
        let kinds = code.diff.map { DiffLook.kinds(of: wrapped, format: $0) }
        for (index, line) in wrapped.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index == code.restart { sides = LexSides() }
            // A diff's headers are no code; each file's lines start afresh after its header.
            let kind = kinds.map { $0.indices.contains(index) ? $0[index] : .kept } ?? .kept
            if kind == .header { sides = LexSides() }
            guard !code.plainLines.contains(index), kind != .header, kind != .hunk else {
                lines.append((line, true, []))
                continue
            }
            // A diff's line is lexed after its marker, on its own side.
            let skip = code.diff.map { DiffLook.markerWidth(kind, format: $0) } ?? 0
            tokens.removeAll(keepingCapacity: true)
            sides.scan(line.dropFirst(skip), kind: kind, lexer: lexer, into: &tokens)
            let styled = tokens.compactMap { token in
                CodeHighlighter.style(of: token.role)
                    .map { (token.range.lowerBound + skip ..< token.range.upperBound + skip, $0) }
            }
            lines.append((line, line.utf8.allSatisfy { $0 < 0x80 }, styled))
        }
    }

    /// The accents of `row`, its columns counted from the start of the drawn line, `inset` columns in; each a token's colour over
    /// `base`, so output stays dim and the block's background shows through.
    mutating func accents(for row: TextWrap.Row, inset: Int, over base: Style) -> [ScreenComposer.Accent] {
        guard lines.indices.contains(row.line), !lines[row.line].tokens.isEmpty else { return [] }
        let start = byte(at: row.line, offset: row.offset)
        let end = start + row.text.utf8.count
        var result: [ScreenComposer.Accent] = []
        let columns = Self.columns(of: row.text)
        for token in lines[row.line].tokens where token.bytes.upperBound > start && token.bytes.lowerBound < end {
            let low = columns(Swift.max(token.bytes.lowerBound, start) - start)
            let high = columns(Swift.min(token.bytes.upperBound, end) - start)
            if high > low {
                result.append(
                    ScreenComposer.Accent(
                        columns: inset + low ..< inset + high,
                        style: Self.style(token.style, over: base)
                    )
                )
            }
        }
        return result
    }

    /// The byte offset of grapheme `offset` in hard line `line`, walking on from the cursor when it is on the same line.
    private mutating func byte(at line: Int, offset: Int) -> Int {
        if cursor.line != line || cursor.offset > offset { cursor = (line, 0, 0) }
        let text = lines[line].text
        if lines[line].ascii {
            cursor = (line, offset, offset)
            return offset
        }
        var index = text.utf8.index(text.startIndex, offsetBy: cursor.byte)
        while cursor.offset < offset, index < text.endIndex {
            let next = text.index(after: index)
            cursor.byte += text.utf8.distance(from: index, to: next)
            cursor.offset += 1
            index = next
        }
        return cursor.byte
    }

    /// A function from a byte offset in `text` to the column it starts at: the byte count itself for printable ASCII, else a table
    /// of each grapheme's first byte and column.
    private static func columns(of text: String) -> (Int) -> Int {
        if text.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return { $0 } }
        var starts: [(byte: Int, column: Int)] = []
        var byte = 0
        var column = 0
        for character in text {
            starts.append((byte, column))
            byte += character.utf8.count
            column += UnicodeWidth.displayWidth(of: character)
        }
        starts.append((byte, column))
        return { offset in starts.first { $0.byte >= offset }?.column ?? column }
    }

    private static func style(_ token: Style, over base: Style) -> Style {
        var style = base
        if token.fg != Style().fg { style.fg = token.fg }
        style.dim = base.dim || token.dim
        style.italic = base.italic || token.italic
        style.bold = base.bold || token.bold
        return style
    }
}
