internal import Foundation
internal import TerminalKitText

/// File paths found in a row of text, so the row can draw them as terminal hyperlinks (roadmap 0075).
///
/// A path is a word that starts with `/` or `~/`, at the start of the row, after a space, a quote, a bracket or `=`.
/// A `:line` or `:line:column` after it (a compiler's location) and trailing punctuation are not part of the link.
/// The text is not rewritten: the row shows what the tool printed, and only the path part becomes clickable. A relative
/// path is not linked, because the row does not know its directory.
enum PathLinks {
    /// A run of columns that opens `uri`.
    struct Link: Sendable, Equatable {
        var columns: Range<Int>
        var uri: String
    }

    /// What may stand before a path, and what ends one.
    private static let before = " \t\"'([=<`"
    private static let stops = " \t\"')]<>`,;|"

    /// Finds the paths in one row of text.
    /// - Parameters:
    ///   - text: one row.
    ///   - home: what `~` means.
    /// - Returns: the links, left to right.
    static func links(in text: String, home: String = NSHomeDirectory()) -> [Link] {
        let paths = pathLinks(in: text, home: home)
        guard text.contains(":") || text.contains("@") else { return paths }
        let addresses = AddressLinks.links(in: text)
            .filter { found in
                !paths.contains { $0.columns.overlaps(found.columns) }
            }
        return (paths + addresses).sorted { $0.columns.lowerBound < $1.columns.lowerBound }
    }

    /// The `/…` and `~/…` paths in one row.
    private static func pathLinks(in text: String, home: String) -> [Link] {
        guard text.contains("/") else { return [] }
        let characters = Array(text)
        var result: [Link] = []
        var column = 0
        var index = 0
        while index < characters.count {
            let start = index
            let startColumn = column
            let boundary = start == 0 || before.contains(characters[start - 1])
            guard boundary, isStart(characters, at: start) else {
                column += UnicodeWidth.displayWidth(of: String(characters[index]))
                index += 1
                continue
            }
            var end = start
            var width = 0
            while end < characters.count, !stops.contains(characters[end]), !isControl(characters[end]) {
                width += UnicodeWidth.displayWidth(of: String(characters[end]))
                end += 1
            }
            // Cut a trailing `:12` or `:12:5` and sentence punctuation.
            var path = Array(characters[start ..< end])
            var kept = path.count
            while kept > 0,
                [".", ":", "!", "?"].contains(path[kept - 1]) || path[kept - 1].isNumber && hasLocation(path, kept)
            { kept -= 1 }
            path = Array(path[0 ..< kept])
            if path.count > 1, let uri = uri(String(path), home: home) {
                let shown = path.reduce(0) { $0 + UnicodeWidth.displayWidth(of: String($1)) }
                result.append(Link(columns: startColumn ..< startColumn + shown, uri: uri))
            }
            column += width
            index = end
        }
        return result
    }

    private static func isStart(_ characters: [Character], at index: Int) -> Bool {
        if characters[index] == "/" {
            // `//` is a comment or a URL's authority, not a path.
            return index + 1 < characters.count && characters[index + 1] != "/"
        }
        return characters[index] == "~" && index + 1 < characters.count && characters[index + 1] == "/"
    }

    /// Whether the digits ending at `kept` follow a colon, so they are a line or column number.
    private static func hasLocation(_ path: [Character], _ kept: Int) -> Bool {
        var cursor = kept
        while cursor > 0, path[cursor - 1].isNumber { cursor -= 1 }
        return cursor > 0 && cursor < kept && path[cursor - 1] == ":"
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.value < 0x20 || (0x7F ... 0x9F).contains($0.value) }
    }

    /// The `file://` URI for `path`, percent-encoded, or nil when it holds a control character.
    static func uri(_ path: String, home: String) -> String? {
        let absolute = path.hasPrefix("~/") ? home + path.dropFirst(1) : path
        guard !absolute.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F ... 0x9F).contains($0.value) })
        else { return nil }
        let clean = (absolute as NSString).standardizingPath
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return "file://" + encoded
    }
}
