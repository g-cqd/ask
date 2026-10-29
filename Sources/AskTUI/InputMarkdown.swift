internal import AemiMarkdown
internal import TerminalKitMarkdown
internal import TerminalKitStyle

/// Markdown colour for the draft (roadmap 0085 proposal 4, 0151): colour only, so every character stays as typed and editing, the cursor
/// and copy are untouched. The text of a mark takes the style a reply would draw it in (TerminalKit's theme), and every character no text
/// covers, which is a marker (`**`, `#`, backticks, a fence, `>`, `- `, a link's brackets), is dimmed. A setext heading is left plain: its
/// meaning comes from the line typed after it.
enum InputMarkdown {
    struct Span: Equatable {
        /// Character offsets into the draft, the unit the editor's cursor uses.
        var characters: Range<Int>
        var style: Style
    }

    /// The styled stretches of `text`, in order; empty for plain prose.
    /// - Complexity: O(n) in the draft's bytes: one parse, one walk.
    static func spans(of text: String) -> [Span] {
        let bytes = Array(text.utf8)
        guard bytes.contains(where: { markerBytes[Int($0)] }) else { return [] }
        let document = MarkdownParser.parse(bytes, extensions: ScreenComposer.markdownExtensions)
        // One byte per source byte: 0 not covered by any leaf (a marker, or space), 1 plain text, k + 2 the k-th style of `table`.
        var codes = [UInt8](repeating: 0, count: bytes.count)
        var table: [Style] = []
        var walk = Walk(theme: .standard, bytes: bytes)
        for event in document.events {
            guard let (range, style) = walk.step(event) else { continue }
            var code: UInt8 = 1
            if let style {
                if let found = table.firstIndex(of: style) {
                    code = UInt8(found + 2)
                } else if table.count < 250 {
                    table.append(style)
                    code = UInt8(table.count + 1)
                }
            }
            for index in range where index < codes.count { codes[index] = code }
        }
        table.append(markerStyle)
        let marker = UInt8(table.count + 1)
        for index in codes.indices where codes[index] == 0 && !isSpace(bytes[index]) { codes[index] = marker }
        return characterSpans(codes, table: table, in: text, ascii: !bytes.contains { $0 >= 0x80 })
    }

    /// How a marker is drawn: dim, so the text it marks reads first. (The theme's `marker` is the colour of a drawn list bullet.)
    static let markerStyle = Style(dim: true)

    /// The bytes some construct starts with; a draft with none of them is prose, and is not parsed.
    private static let markerBytes: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for byte in "*_`#[]>~|!<-+=0123456789:\\&$".utf8 { table[Int(byte)] = true }
        return table
    }()

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }

    /// Byte codes merged into runs of characters. A character takes the code of its first byte; for an ASCII draft each byte is a
    /// character, and the draft is not walked by grapheme.
    private static func characterSpans(_ codes: [UInt8], table: [Style], in text: String, ascii: Bool) -> [Span] {
        var spans: [Span] = []
        var start = 0
        var current: UInt8 = 0
        func close(at end: Int) {
            if current >= 2, end > start {
                spans.append(Span(characters: start ..< end, style: table[Int(current) - 2]))
            }
        }
        func visit(_ code: UInt8, at offset: Int) {
            guard code != current else { return }
            close(at: offset)
            current = code
            start = offset
        }
        if ascii {
            for offset in codes.indices { visit(codes[offset], at: offset) }
            close(at: codes.count)
        } else {
            var byte = 0
            var offset = 0
            for character in text {
                visit(codes[byte], at: offset)
                byte += character.utf8.count
                offset += 1
            }
            close(at: offset)
        }
        return spans
    }

    /// The containers open at each point of a walk, and the style each leaf's bytes take.
    private struct Walk {
        let theme: MarkdownTheme
        let bytes: [UInt8]
        private var open: [MarkdownNode] = []
        /// Per open heading: whether it is an ATX heading, decided at its first leaf.
        private var atx: Bool?

        init(theme: MarkdownTheme, bytes: [UInt8]) {
            self.theme = theme
            self.bytes = bytes
        }

        /// The bytes a leaf covers and their style (nil for plain text), or nil for an event that covers none.
        mutating func step(_ event: MarkdownEvent) -> (Range<Int>, Style?)? {
            switch event {
                case .enter(let node):
                    open.append(node)
                    if node.kind == .heading { atx = nil }
                    return nil
                case .exit:
                    _ = open.popLast()
                    return nil
                case .leaf(let node):
                    guard !node.range.isEmpty else { return nil }
                    return (node.range, style(of: node))
            }
        }

        private mutating func style(of leaf: MarkdownNode) -> Style? {
            switch leaf.kind {
                case .codeLine: return theme.code
                case .infoString: return theme.codeLabel
                case .linkDestination, .linkTitle: return theme.linkTarget
                case .htmlInline: return theme.html
                default: break
            }
            var style: Style?
            func add(_ next: Style) { style = Self.merged(style, next) }
            for node in open {
                switch node.kind {
                    case .codeSpan: return theme.code
                    case .link, .image, .autolink: add(theme.link)
                    case .strong: add(theme.strong)
                    case .emphasis: add(theme.emphasis)
                    case .strikethrough: add(theme.strikethrough)
                    case .heading where isATX(leaf):
                        add(theme.headings[Swift.min(Swift.max(node.payload, 1), theme.headings.count) - 1])
                    default: break
                }
            }
            return style
        }

        /// Whether the open heading starts with `#` on its line: decided once, at its first leaf.
        private mutating func isATX(_ leaf: MarkdownNode) -> Bool {
            if let atx { return atx }
            var index = leaf.range.lowerBound - 1
            while index >= 0, bytes[index] != 0x0A, bytes[index] != 0x23 { index -= 1 }
            let found = index >= 0 && bytes[index] == 0x23
            atx = found
            return found
        }

        private static func merged(_ base: Style?, _ next: Style) -> Style {
            guard var style = base else { return next }
            if next.bold { style.bold = true }
            if next.italic { style.italic = true }
            if next.strikethrough { style.strikethrough = true }
            if next.underline != style.underline, next.underline != Style().underline {
                style.underline = next.underline
            }
            if next.fg != Style().fg { style.fg = next.fg }
            return style
        }
    }
}
