internal import TerminalKitMarkdown
internal import TerminalKitStyle

/// A known name at the start of a word, drawn as a token in the draft and in the person's message: `/skill:name` (roadmap 0185), `#t3`
/// and `#i2` (0186). What is drawn so is attached when the message is sent, so what looks like a link is exactly what will be. The same
/// word rule as the sending side: after the start or white space, sentence punctuation not part of it, an unknown one left plain.
enum SkillTokens {
    /// A link's colour (the Markdown theme's), since a token stands for something attached; not its underline, which TerminalKit writes
    /// as `4:1`, a form some terminals (and the probes' emulator) print as text.
    static let style = Style(fg: MarkdownTheme.standard.link.fg)
    /// The characters a token starts with.
    static let sigils: Set<Character> = ["/", "#"]

    /// The character ranges of the words in `text` that `known` holds, sigil and all (`/skill:debugging`, `#t3`).
    static func ranges(in text: String, known: Set<String>) -> [Range<Int>] {
        guard !known.isEmpty, text.contains(where: { sigils.contains($0) }) else { return [] }
        var ranges: [Range<Int>] = []
        var previous: Character = " "
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            if previous.isWhitespace, sigils.contains(text[index]) {
                let word = text[index...].prefix { !$0.isWhitespace }
                let name = String(word.reversed().drop { ",.;:!?)]}\"'".contains($0) }.reversed())
                if known.contains(name) { ranges.append(offset ..< offset + name.count) }
                index = text.index(index, offsetBy: word.count)
                offset += word.count
                previous = word.last ?? " "
                continue
            }
            previous = text[index]
            index = text.index(after: index)
            offset += 1
        }
        return ranges
    }
}
