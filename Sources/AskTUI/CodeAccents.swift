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
    /// The output's own links (note n30), by hard line: byte ranges as the wrap measures them, and their targets.
    private var links: [[(bytes: Range<Int>, uri: String)]] = []

    init(_ text: String, code: FileCode) {
        let wrapped = text.utf8.contains(0x09) ? text.replacing("\t", with: "    ") : text
        if let spans = code.spans {
            (lines, links) = Self.lines(
                wrapped,
                spans: spans,
                tabs: text.split(separator: "\n", omittingEmptySubsequences: false)
            )
            return
        }
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

    /// The output's own spans (note n30), each line's moved by the three bytes every tab before it became, as the wrap measures it.
    /// A span that only links is a link, not a token: it changes nothing the row draws.
    private static func lines(_ wrapped: String, spans: [[OutputEscapes.Span]], tabs original: [Substring]) -> (
        [(text: Substring, ascii: Bool, tokens: [(bytes: Range<Int>, style: Style)])],
        [[(bytes: Range<Int>, uri: String)]]
    ) {
        var lines: [(text: Substring, ascii: Bool, tokens: [(bytes: Range<Int>, style: Style)])] = []
        var links: [[(bytes: Range<Int>, uri: String)]] = []
        for (index, line) in wrapped.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineSpans = spans.indices.contains(index) ? spans[index] : []
            let tabs =
                original.indices.contains(index)
                ? original[index].utf8.indices
                    .compactMap { position in
                        original[index].utf8[position] == 0x09
                            ? original[index].utf8.distance(from: original[index].startIndex, to: position) : nil
                    } : []
            let moved = { (byte: Int) in byte + 3 * tabs.count { $0 < byte } }
            let bytes = { (span: OutputEscapes.Span) in moved(span.bytes.lowerBound) ..< moved(span.bytes.upperBound) }
            let tokens = lineSpans.filter { Self.draws($0.style) }.map { (bytes: bytes($0), style: $0.style) }
            lines.append((line, line.utf8.allSatisfy { $0 < 0x80 }, tokens))
            links.append(lineSpans.compactMap { span in span.style.link.map { (bytes: bytes(span), uri: $0) } })
        }
        return (lines, links)
    }

    /// The links of `row` (note n30): each span's link over the columns it covers.
    mutating func links(for row: TextWrap.Row, inset: Int) -> [PathLinks.Link] {
        guard links.indices.contains(row.line), !links[row.line].isEmpty else { return [] }
        let start = byte(at: row.line, offset: row.offset)
        let end = start + row.text.utf8.count
        let columns = Self.columns(of: row.text)
        return links[row.line]
            .compactMap { link in
                let low = columns(Swift.max(link.bytes.lowerBound, start) - start)
                let high = columns(Swift.min(link.bytes.upperBound, end) - start)
                return high > low ? PathLinks.Link(columns: inset + low ..< inset + high, uri: link.uri) : nil
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
        for token in lines[row.line].tokens where token.bytes.overlaps(start ..< end) {
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
        if token.underline != .none { style.underline = token.underline }
        style.strikethrough = base.strikethrough || token.strikethrough
        return style
    }

    /// Whether a token changes how its columns look: one that only links leaves that to the row's links.
    private static func draws(_ token: Style) -> Bool {
        var look = token
        look.link = nil
        return look != Style()
    }
}
