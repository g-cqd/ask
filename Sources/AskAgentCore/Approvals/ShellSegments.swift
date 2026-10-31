/// The commands of a shell line, for ``CommandWords``: split at `;`, `|`, `&` and line ends, except inside quotes, after a backslash, and
/// in a heredoc's body, which is data the command reads. Every rule leans toward naming more commands, never fewer: a body starts only at
/// the next line, and ends at the first line that is its delimiter once spaces and tabs are trimmed (where a shell might read on).
struct ShellSegments {
    private let characters: [Character]
    private var index = 0
    private var segments: [String] = []
    private var current = ""
    /// The delimiters of the heredocs opened on the current line, whose bodies start at its end.
    private var bodies: [String] = []

    private init(_ line: String) { characters = Array(line) }

    /// The segments of `line`, in order; empty ones included.
    static func split(_ line: String) -> [String] {
        var scanner = ShellSegments(line)
        scanner.scan()
        return scanner.segments + [scanner.current]
    }

    private mutating func scan() {
        while index < characters.count {
            switch characters[index] {
                case "'": quoted(closing: "'", escapes: false)
                case "\"": quoted(closing: "\"", escapes: true)
                case "\\": escaped()
                case "<" where opensHereString: hereString()
                case "<" where opensHeredoc: heredoc()
                case "\n":
                    endSegment()
                    skipBodies()
                case ";", "|", "&": endSegment()
                default:
                    current.append(characters[index])
                    index += 1
            }
        }
    }

    private mutating func endSegment() {
        segments.append(current)
        current = ""
        index += 1
    }

    /// A quoted string, kept whole: in double quotes a backslash keeps the next character in the string, in single quotes it does not.
    private mutating func quoted(closing: Character, escapes: Bool) {
        current.append(characters[index])
        index += 1
        while index < characters.count, characters[index] != closing {
            if escapes, characters[index] == "\\", index + 1 < characters.count {
                current.append(characters[index])
                index += 1
            }
            current.append(characters[index])
            index += 1
        }
        if index < characters.count {
            current.append(closing)
            index += 1
        }
    }

    /// A backslash outside quotes: the next character is part of a word, and a line end continues the command.
    private mutating func escaped() {
        if index + 1 < characters.count {
            current.append(characters[index + 1] == "\n" ? " " : characters[index + 1])
        }
        index += 2
    }

    /// `<<<` here: a here-string, whose word is on this line. Read before ``opensHeredoc``, or its last two `<` would open a heredoc whose
    /// body hides the next lines' commands.
    private var opensHereString: Bool {
        index + 2 < characters.count && characters[index + 1] == "<" && characters[index + 2] == "<"
    }

    /// A here-string's `<<<`, kept as written.
    private mutating func hereString() {
        current += "<<<"
        index += 3
    }

    /// `<<` here; a here-string's `<<<` was read before this is asked.
    private var opensHeredoc: Bool { index + 1 < characters.count && characters[index + 1] == "<" }

    /// `<<WORD`, `<<-WORD`, `<< 'WORD'`: notes the delimiter, whose body starts at the end of the line.
    private mutating func heredoc() {
        index += 2
        if index < characters.count, characters[index] == "-" { index += 1 }
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        var delimiter = ""
        while index < characters.count, !characters[index].isWhitespace, !";|&<>()".contains(characters[index]) {
            if !"'\"\\".contains(characters[index]) { delimiter.append(characters[index]) }
            index += 1
        }
        current += " <<" + delimiter
        if !delimiter.isEmpty { bodies.append(delimiter) }
    }

    /// Past the bodies of the heredocs the line just ended opened, in order.
    private mutating func skipBodies() {
        for delimiter in bodies {
            while index < characters.count {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                let line = characters[start ..< index].drop { $0 == " " || $0 == "\t" }
                let trimmed = line.reversed().drop { $0 == " " || $0 == "\t" }.reversed()
                index += 1
                if String(trimmed) == delimiter { break }
            }
        }
        bodies = []
    }
}
