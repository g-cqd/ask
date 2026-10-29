/// Turns a byte offset into a message into the (hard line, grapheme offset) a selection names, counted as the copied text counts them: lines
/// split at line feeds, a tab four graphemes (``TranscriptContent/hardLines(of:)``). It is what rendered Markdown, whose runs name source bytes,
/// needs to say which text a row shows (roadmap 0065).
///
/// A line of ASCII without a tab maps byte to grapheme directly; any other line has a table of its graphemes' bytes, built the first time it is
/// asked for and searched by halving.
struct MarkdownSourceLines {
    /// Where each line starts, in bytes; one more entry than lines, the end of the text plus one.
    private let starts: [Int]
    private let text: String
    /// A line's graphemes as (first byte, grapheme offset) pairs, then its end, for the lines that are not plain ASCII; built as asked for.
    private var tables: [Int: [(byte: Int, offset: Int)]] = [:]
    /// Whether each line maps byte to grapheme directly.
    private let isPlain: [Bool]

    init(_ text: String) {
        self.text = text
        var starts = [0]
        var isPlain: [Bool] = []
        var plain = true
        for (index, byte) in text.utf8.enumerated() {
            if byte == 0x0A {
                starts.append(index + 1)
                isPlain.append(plain)
                plain = true
            } else if byte >= 0x80 || byte == 0x09 || byte == 0x0D {
                plain = false
            }
        }
        isPlain.append(plain)
        starts.append(text.utf8.count + 1)
        self.starts = starts
        self.isPlain = isPlain
    }

    /// The line `byte` is on, and its grapheme offset in it; a byte inside a grapheme counts as that grapheme's start.
    mutating func position(of byte: Int) -> (line: Int, offset: Int) {
        let line = self.line(of: byte)
        return (line, offset(of: byte, on: line))
    }

    /// How many graphemes of line `line` the bytes from `lower` up to `upper` hold; the part past the line's end does not count.
    mutating func count(on line: Int, from lower: Int, to upper: Int) -> Int {
        let end = Swift.min(upper, starts[line + 1] - 1)
        guard end > lower else { return 0 }
        return offset(of: end, on: line) - offset(of: lower, on: line)
    }

    /// The line `byte` is on: the last line that starts at or before it.
    private func line(of byte: Int) -> Int {
        var low = 0
        var high = starts.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= byte { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The grapheme offset of `byte` on `line`; a byte at or past the line's end is the line's length.
    private mutating func offset(of byte: Int, on line: Int) -> Int {
        let start = starts[line]
        let relative = Swift.max(0, Swift.min(byte, starts[line + 1] - 1) - start)
        guard !isPlain[line] else { return relative }
        let table = self.table(of: line)
        var low = 0
        var high = table.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if table[middle].byte <= relative { low = middle } else { high = middle - 1 }
        }
        return table[low].offset
    }

    /// The line's graphemes, each with its first byte and its offset, then its end.
    private mutating func table(of line: Int) -> [(byte: Int, offset: Int)] {
        if let table = tables[line] { return table }
        let utf8 = text.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: starts[line])
        let upper = utf8.index(utf8.startIndex, offsetBy: starts[line + 1] - 1)
        var table: [(byte: Int, offset: Int)] = []
        var byte = 0
        var offset = 0
        for character in text[lower ..< upper] {
            table.append((byte, offset))
            byte += character.utf8.count
            offset += character == "\t" ? 4 : 1
        }
        table.append((byte, offset))
        tables[line] = table
        return table
    }
}
