/// A text's lines, found from its bytes (roadmap 0152): what `split(separator: "\n", omittingEmptySubsequences: false)` gives,
/// without walking the text grapheme by grapheme. A line feed is a grapheme of its own, except after a carriage return, where the
/// two are one grapheme that the character split does not cut at; so this does not cut there either.
enum LineSplit {
    static func lines(of text: String) -> [Substring] {
        let utf8 = text.utf8
        let bytes = utf8.span
        var lines: [Substring] = []
        var start = utf8.startIndex
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A, index == 0 || bytes[index - 1] != 0x0D {
                let end = utf8.index(utf8.startIndex, offsetBy: index)
                lines.append(text[start ..< end])
                start = utf8.index(after: end)
            }
            index += 1
        }
        lines.append(text[start...])
        return lines
    }
}
