internal import TerminalKitMarkdown
internal import TerminalKitStyle

/// A known `/skill:name` at the start of a word, drawn as a token in the draft and in the person's message (roadmap 0185): the skill is
/// attached when the message is sent, so what looks like a link is exactly what will be. The same word rule as the sending side's
/// `SkillInvocation`: after the start or white space, sentence punctuation not part of the name, an unknown name left plain.
enum SkillTokens {
    static let prefix = "/skill:"
    /// A link's look (the Markdown theme's), since the token stands for something attached.
    static let style = MarkdownTheme.standard.link

    /// The character ranges of the tokens in `text` whose command name (`skill:name`) is in `known`.
    static func ranges(in text: String, known: Set<String>) -> [Range<Int>] {
        guard !known.isEmpty, text.contains(prefix) else { return [] }
        var ranges: [Range<Int>] = []
        var previous: Character = " "
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            if previous.isWhitespace, text[index...].hasPrefix(prefix) {
                let word = text[index...].prefix { !$0.isWhitespace }
                let name = String(word.reversed().drop { ",.;:!?)]}\"'".contains($0) }.reversed())
                if known.contains(String(name.dropFirst())) { ranges.append(offset ..< offset + name.count) }
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
