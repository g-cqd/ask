/// Reads the inline collection syntax YAML and TOML share: `[a, "b c", [d]]` and `{key: value, other = value}`. Never fails: text that is not
/// well formed comes back as the scalar it was.
struct FlowParser {
    private let characters: [Character]
    private var position = 0
    private var depth = 0
    /// How deep a list or map may nest; deeper than this is read as text, so a file of brackets cannot exhaust the stack.
    static let maximumDepth = 32

    /// A value read from `text`, which should start with `[` or `{`, or be a scalar.
    static func parse(_ text: String) -> DefinitionValue {
        var parser = FlowParser(characters: Array(text.trimmingWhitespace()))
        let value = parser.value()
        return parser.atEnd ? value : .text(text.trimmingWhitespace())
    }

    private init(characters: [Character]) { self.characters = characters }

    private var atEnd: Bool {
        var look = position
        while look < characters.count, characters[look].isWhitespace { look += 1 }
        return look >= characters.count
    }

    private mutating func skipSpace() {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
    }

    private mutating func value() -> DefinitionValue {
        skipSpace()
        guard position < characters.count else { return .text("") }
        if depth >= Self.maximumDepth, characters[position] == "[" || characters[position] == "{" {
            defer { position = characters.count }
            return .text(String(characters[position...]))
        }
        switch characters[position] {
            case "[": return list()
            case "{": return map()
            case "\"", "'": return .text(quoted())
            default: return .text(plain())
        }
    }

    /// The elements up to the closing bracket, each read by `read`: commas are skipped, and an element that consumes nothing is stepped over so a
    /// malformed list always ends.
    private mutating func elements(closing: Character, read: (inout FlowParser) -> Void) {
        position += 1
        depth += 1
        defer { depth -= 1 }
        while true {
            skipSpace()
            guard position < characters.count else { return }
            if characters[position] == closing {
                position += 1
                return
            }
            if characters[position] == "," {
                position += 1
                continue
            }
            let before = position
            read(&self)
            if position == before { position += 1 }
        }
    }

    private mutating func list() -> DefinitionValue {
        var items: [DefinitionValue] = []
        elements(closing: "]") { items.append($0.value()) }
        return .list(items)
    }

    private mutating func map() -> DefinitionValue {
        var entries: [DefinitionEntry] = []
        elements(closing: "}") { parser in
            let isQuoted = parser.characters[parser.position] == "\"" || parser.characters[parser.position] == "'"
            let key = isQuoted ? parser.quoted() : parser.plain(stoppingAt: [":", "=", ",", "}"])
            parser.skipSpace()
            if parser.position < parser.characters.count,
                parser.characters[parser.position] == ":" || parser.characters[parser.position] == "="
            {
                parser.position += 1
                entries.append(DefinitionEntry(key: key.trimmingWhitespace(), value: parser.value()))
            } else if !key.isEmpty {
                entries.append(DefinitionEntry(key: key.trimmingWhitespace(), value: .text("")))
            }
        }
        return .map(entries)
    }

    private mutating func quoted() -> String {
        let open = characters[position]
        position += 1
        var text = ""
        while position < characters.count {
            let character = characters[position]
            position += 1
            if character == open {
                if open == "'", position < characters.count, characters[position] == "'" {
                    text.append("'")
                    position += 1
                    continue
                }
                return text
            }
            if character == "\\", open == "\"", position < characters.count {
                if characters[position] == "u", let scalar = Self.unicodeScalar(characters, after: position) {
                    text.unicodeScalars.append(scalar)
                    position += 5
                } else {
                    text.append(Self.unescape(characters[position]))
                    position += 1
                }
            } else {
                text.append(character)
            }
        }
        return text
    }

    private mutating func plain(stoppingAt stops: Set<Character> = [",", "]", "}"]) -> String {
        var text = ""
        while position < characters.count, !stops.contains(characters[position]) {
            text.append(characters[position])
            position += 1
        }
        return text.trimmingWhitespace()
    }

    /// The scalar a `\uXXXX` escape names, where the `u` is at `index`.
    static func unicodeScalar(_ characters: [Character], after index: Int) -> Unicode.Scalar? {
        guard index + 4 < characters.count else { return nil }
        let digits = String(characters[index + 1 ... index + 4])
        return UInt32(digits, radix: 16).flatMap(Unicode.Scalar.init)
    }

    static func unescape(_ character: Character) -> Character {
        switch character {
            case "n": "\n"
            case "t": "\t"
            case "r": "\r"
            case "0": "\0"
            default: character
        }
    }
}
