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
        /// The line and column written after a path (`a.swift:12:5`), for an opener that takes them (roadmap 0216); nil when none was.
        var line: Int?
        var column: Int?

        init(columns: Range<Int>, uri: String, line: Int? = nil, column: Int? = nil) {
            self.columns = columns
            self.uri = uri
            self.line = line
            self.column = column
        }

        /// A link from an address that may carry its place (``PathLinks/carrying(_:on:)``): the place is taken off, so the terminal
        /// is given the file alone.
        init(columns: Range<Int>, carrying address: String) {
            guard address.hasPrefix("file://"), let hash = address.lastIndex(of: "#"),
                let place = Self.place(address[address.index(after: hash)...])
            else {
                self.init(columns: columns, uri: address)
                return
            }
            self.init(columns: columns, uri: String(address[..<hash]), line: place.line, column: place.column)
        }

        /// `L12` or `L12C5`; nil for anything else.
        private static func place(_ text: Substring) -> (line: Int, column: Int?)? {
            guard text.first == "L" else { return nil }
            let parts = text.dropFirst().split(separator: "C", maxSplits: 1, omittingEmptySubsequences: false)
            func number(_ part: Substring) -> Int? {
                (1 ... 9).contains(part.count) && part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
            }
            guard let first = parts.first, let line = number(first) else { return nil }
            guard parts.count == 2 else { return (line, nil) }
            guard let column = number(parts[1]) else { return nil }
            return (line, column)
        }

        /// What a click opens: the address, with the place in the file after it as `#L12C5`. Only a click takes this form; the
        /// terminal is given ``uri``.
        var target: String {
            guard let line, uri.hasPrefix("file://") else { return uri }
            return uri + "#L\(line)" + (column.map { "C\($0)" } ?? "")
        }
    }

    /// What may stand before a path, and what ends one.
    private static let before = " \t\"'([=<`"
    private static let stops = " \t\"')]<>`,;|"

    /// Finds the paths in one row of text.
    /// - Parameters:
    ///   - text: one row.
    ///   - home: what `~` means.
    /// - Returns: the links, left to right.
    /// The scheme of a link to one of ask's commands: a click fills an empty input with it, and the terminal is not given it.
    static let commandScheme = "ask-command:/"

    static func links(in text: String, home: String = NSHomeDirectory(), commands: Set<String> = []) -> [Link] {
        let paths = LinkCandidates.mayHoldPath(text) ? pathLinks(in: text, home: home, commands: commands) : []
        guard LinkCandidates.mayHoldAddress(text), text.contains(":") || text.contains("@") else { return paths }
        let addresses = AddressLinks.links(in: text)
            .filter { found in
                !paths.contains { $0.columns.overlaps(found.columns) }
            }
        return (paths + addresses).sorted { $0.columns.lowerBound < $1.columns.lowerBound }
    }

    /// The `/…` and `~/…` paths in one row, and the `/name`s that are `commands`.
    private static func pathLinks(in text: String, home: String, commands: Set<String>) -> [Link] {
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
            let target: String? =
                switch word(path, commands) {
                    case .command(let name): commandScheme + name
                    case .prose: nil
                    case .path: uri(String(path), home: home)
                }
            if path.count > 1, let uri = target {
                let shown = path.reduce(0) { $0 + UnicodeWidth.displayWidth(of: String($1)) }
                result.append(Link(columns: startColumn ..< startColumn + shown, uri: uri))
            }
            column += width
            index = end
        }
        return result
    }

    /// What a path word is: one of `commands` (`/name`), a single `/word` in prose (note n11: not a command, nor a path because it
    /// starts with a slash, unless it is one of `rootEntries`), or a path.
    private enum Word {
        case command(String)
        case prose
        case path
    }

    private static func word(_ path: [Character], _ commands: Set<String>) -> Word {
        guard path.first == "/", !path.dropFirst().contains("/") else { return .path }
        let name = String(path.dropFirst())
        if commands.contains(name) { return .command(name) }
        return rootEntries.contains(name) ? .path : .prose
    }

    /// The folders at the root of macOS and Linux, a single `/word` that is a path: named rather than looked for on the disk, so a row
    /// draws the same on every machine.
    private static let rootEntries = Set(
        "Applications Library System Users Volumes Network bin boot cores dev etc home lib mnt nix opt private proc root run sbin srv sys tmp usr var"
            .split(separator: " ").map(String.init)
    )

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
