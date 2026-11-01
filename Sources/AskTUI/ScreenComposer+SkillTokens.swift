internal import TerminalKitStyle
internal import TerminalKitText

/// The person's message with its named skills drawn as tokens (roadmap 0185), on top of the message's bold look.
extension ScreenComposer {
    static func withSkillTokens(_ rows: [Line], known: Set<String>) -> [Line] {
        guard !known.isEmpty else { return rows }
        var look = SkillTokens.style
        look.bold = true
        return rows.map { row in
            let ranges = SkillTokens.ranges(in: row.text, known: known)
            guard !ranges.isEmpty else { return row }
            var row = row
            let characters = Array(row.text)
            for range in ranges {
                let start = UnicodeWidth.displayWidth(of: String(characters[..<range.lowerBound]))
                let width = UnicodeWidth.displayWidth(of: String(characters[range]))
                row.accents.append(Accent(columns: start ..< start + width, style: look))
            }
            return row
        }
    }
}
