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
        let lower = text.index(text.startIndex, offsetBy: visible.lowerBound, limitedBy: text.endIndex) ?? text.endIndex
        let upper = text.index(lower, offsetBy: visible.count, limitedBy: text.endIndex) ?? text.endIndex
        let bytes = text.utf8
        let start = restart(in: bytes, before: bytes.distance(from: bytes.startIndex, to: lower))
        var end = bytes.distance(from: bytes.startIndex, to: upper)
        while end < bytes.count, bytes[bytes.index(bytes.startIndex, offsetBy: end)] != 0x0A { end += 1 }
        let startIndex = bytes.index(bytes.startIndex, offsetBy: start)
        let endIndex = bytes.index(bytes.startIndex, offsetBy: end)
        let shift = visible.lowerBound - text.distance(from: startIndex, to: lower)
        return spans(of: String(text[startIndex ..< endIndex]))
            .map { span in
                Span(
                    characters: span.characters.lowerBound + shift ..< span.characters.upperBound + shift,
                    style: span.style)
            }
    }

    /// The byte offset of the last line at or before `limit` where parsing can restart: 0 when there is none.
    /// - Complexity: O(limit), one pass over the bytes before the window.
    private static func restart(in bytes: String.UTF8View, before limit: Int) -> Int {
        var safe = 0
        var fence: (byte: UInt8, length: Int)?
        var lineStart = 0
        var previousBlank = true
        var index = bytes.startIndex
        var offset = 0
        var line: [UInt8] = []
        while offset <= limit, index < bytes.endIndex || offset == bytes.count {
            let atEnd = index == bytes.endIndex
            let byte: UInt8 = atEnd ? 0x0A : bytes[index]
            if byte != 0x0A {
                line.append(byte)
            } else {
                let blank = line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
                let indented = line.first == 0x20 || line.first == 0x09
                // `previousBlank` is false inside a fence, so a line inside one is never a restart.
                if previousBlank, !blank, !indented, lineStart <= limit { safe = lineStart }
                fence = step(fence, line)
                previousBlank = blank && fence == nil
                lineStart = offset + 1
                line.removeAll(keepingCapacity: true)
                if atEnd { break }
            }
            offset += 1
            index = bytes.index(after: index)
        }
        return safe
    }

    /// The fence open after `line`: one opens on a line of three or more backticks or tildes (up to three spaces in), and closes on a line
    /// of at least as many of the same, with nothing after them but spaces.
    private static func step(_ open: (byte: UInt8, length: Int)?, _ line: [UInt8]) -> (byte: UInt8, length: Int)? {
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
            let rest = line[index...].allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
            return byte == open.byte && length >= open.length && rest ? nil : open
        }
        // A backtick fence's info string may not hold a backtick.
        if byte == 0x60, line[index...].contains(0x60) { return nil }
        return (byte, length)
    }
}
