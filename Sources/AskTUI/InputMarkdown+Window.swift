/// The draft coloured only around the rows shown, so a keystroke in a long draft costs the window's parse, not the draft's (roadmap 0151:
/// at 20 KB a whole parse took a keystroke past the 4 ms budget). The window starts at a line where parsing can restart and give the same
/// result: after a blank line, outside any fence, before a line that is not indented (so a list's continuation or indented code is not
/// read out of context); it ends at the end of the last line shown.
extension InputMarkdown {
    /// A draft this short is parsed whole: the window would save nothing measurable.
    static let wholeParseBytes = 8_192

    /// The styled stretches of `text` that fall in `visible` (character offsets), and possibly some around it.
    static func spans(of text: String, visible: Range<Int>) -> [Span] {
        guard text.utf8.count > wholeParseBytes else { return spans(of: text) }
        let lower = index(in: text, ofCharacter: visible.lowerBound)
        let upper = text.index(lower, offsetBy: visible.count, limitedBy: text.endIndex) ?? text.endIndex
        let bytes = text.utf8
        let start = restart(in: text, before: bytes.distance(from: bytes.startIndex, to: lower))
        var end = bytes.distance(from: bytes.startIndex, to: upper)
        while end < bytes.count, bytes[bytes.index(bytes.startIndex, offsetBy: end)] != 0x0A { end += 1 }
        let startIndex = bytes.index(bytes.startIndex, offsetBy: start)
        let endIndex = bytes.index(bytes.startIndex, offsetBy: end)
        let shift = visible.lowerBound - text.distance(from: startIndex, to: lower)
        return spans(of: String(text[startIndex ..< endIndex]))
            .map { span in
                Span(
                    characters: span.characters.lowerBound + shift ..< span.characters.upperBound + shift,
                    style: span.style
                )
            }
    }

    /// The index of character `offset` of `text`. While the text before it is ASCII, without a carriage return (`\r\n` is one
    /// character), the byte offset is the character offset, found by scanning bytes rather than walking characters.
    private static func index(in text: String, ofCharacter offset: Int) -> String.Index {
        let utf8 = text.utf8
        let bytes = utf8.span
        let end = Swift.min(offset, bytes.count)
        var scanned = 0
        while scanned < end, bytes[scanned] < 0x80, bytes[scanned] != 0x0D { scanned += 1 }
        guard scanned == end, offset <= bytes.count else {
            return text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) ?? text.endIndex
        }
        return text.utf8.index(text.startIndex, offsetBy: offset)
    }

    /// The byte offset of the last line at or before `limit` where parsing can restart: 0 when there is none. A line counts once its
    /// end, its line feed or the text's end, is at or before `limit`.
    /// - Complexity: O(limit), one pass over the bytes before the window, read in place.
    private static func restart(in text: String, before limit: Int) -> Int {
        let utf8 = text.utf8
        let bytes = utf8.span
        var safe = 0
        var fence: (byte: UInt8, length: Int)?
        var previousBlank = true
        var lineStart = 0
        while true {
            var end = lineStart
            while end < bytes.count, bytes[end] != 0x0A { end += 1 }
            guard end <= limit else { break }
            let line = bytes.extracting(lineStart ..< end)
            var blank = true
            for index in 0 ..< line.count where line[index] != 0x20 && line[index] != 0x09 && line[index] != 0x0D {
                blank = false
                break
            }
            let indented = line.count > 0 && (line[0] == 0x20 || line[0] == 0x09)
            // `previousBlank` is false inside a fence, so a line inside one is never a restart.
            if previousBlank, !blank, !indented { safe = lineStart }
            fence = step(fence, line)
            previousBlank = blank && fence == nil
            guard end < bytes.count else { break }
            lineStart = end + 1
        }
        return safe
    }

    /// The fence open after `line`: one opens on a line of three or more backticks or tildes (up to three spaces in), and closes on a line
    /// of at least as many of the same, with nothing after them but spaces.
    private static func step(_ open: (byte: UInt8, length: Int)?, _ line: Swift.Span<UInt8>) -> (
        byte: UInt8, length: Int
    )? {
        var index = 0
        while index < line.count, index < 3, line[index] == 0x20 { index += 1 }
        guard index < line.count, line[index] == 0x60 || line[index] == 0x7E else { return open }
        let byte = line[index]
        var length = 0
        while index < line.count, line[index] == byte {
            length += 1
            index += 1
        }
        guard length >= 3 else { return open }
        if let open {
            var rest = true
            for after in index ..< line.count where line[after] != 0x20 && line[after] != 0x09 && line[after] != 0x0D {
                rest = false
                break
            }
            return byte == open.byte && length >= open.length && rest ? nil : open
        }
        // A backtick fence's info string may not hold a backtick.
        for after in index ..< line.count where line[after] == 0x60 { return nil }
        return (byte, length)
    }
}
