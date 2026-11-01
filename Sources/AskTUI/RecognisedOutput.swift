internal import AemiJSON
internal import AemiLexers

/// A tool's output recognised by its content (roadmap 0152, phase 5): JSON that parses, or a unified diff. Nothing else is guessed at,
/// so any other output stays plain.
enum RecognisedOutput: Equatable {
    case json
    /// A unified diff, and the language of its files when they all have one and the same.
    case diff(Language?)

    /// Output larger than this is not recognised: parsing it on every layout would cost more than its colours are worth.
    static let maximumBytes = 1 << 20

    static func recognise(_ text: String) -> RecognisedOutput? {
        guard !text.isEmpty, text.utf8.count <= maximumBytes else { return nil }
        if isJSON(text) { return .json }
        return diffLanguage(text).map { .diff($0) }
    }

    /// Whether `text`, without its surrounding white space, is a JSON object or array.
    private static func isJSON(_ text: String) -> Bool {
        let trimmed = text.utf8.drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        guard let first = trimmed.first, first == UInt8(ascii: "{") || first == UInt8(ascii: "[") else { return false }
        return (try? AemiJSON.parse(Array(trimmed))) != nil
    }

    /// For a unified diff, the language of its files (`.some(nil)` when they have none or several); nil for any other text. A diff has a
    /// `--- ` line, the `+++ ` line right after it, then a hunk header (`@@ -`).
    private static func diffLanguage(_ text: String) -> Language?? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var languages: Set<Language> = []
        var sawHunk = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("--- "), index + 1 < lines.count, lines[index + 1].hasPrefix("+++ ") {
                let new = path(lines[index + 1].dropFirst(4))
                let path = new == "/dev/null" ? self.path(line.dropFirst(4)) : new
                languages.insert(Language(path: String(path), firstLine: nil))
                index += 2
                continue
            }
            if line.hasPrefix("@@ -"), !languages.isEmpty { sawHunk = true }
            index += 1
        }
        guard sawHunk else { return nil }
        return .some(languages.count == 1 && languages.first != .plain ? languages.first : nil)
    }

    /// A header's path without git's `a/` or `b/` and without the timestamp `diff -u` adds after a tab.
    private static func path(_ field: Substring) -> Substring {
        var path = field.split(separator: "\t", maxSplits: 1).first ?? field
        if path.hasPrefix("a/") || path.hasPrefix("b/") { path = path.dropFirst(2) }
        return path
    }
}
