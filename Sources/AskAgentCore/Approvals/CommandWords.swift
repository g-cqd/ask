/// What a session grant for a command line names (roadmap 0134): for each command the line runs, its program and subcommand
/// (`git status`) and the program alone (`git`). A line with a substitution (`$(…)`, a backquote) runs commands that cannot be known in
/// advance, so no grant ever covers it.
public struct CommandWords: Sendable, Equatable {
    /// One command of the line.
    public struct Command: Sendable, Equatable {
        /// `git status`, or the program alone when it has no subcommand.
        public let phrase: String
        public let program: String
    }

    /// The commands, in order.
    public let commands: [Command]
    /// Whether a grant can cover the line.
    public let coverable: Bool

    /// The phrases, in order, without repeats.
    public var phrases: [String] { Self.unique(commands.map(\.phrase)) }
    /// The programs, in order, without repeats.
    public var programs: [String] { Self.unique(commands.map(\.program)) }

    /// The words of `command`.
    public init(_ command: String) {
        var commands: [Command] = []
        for segment in Self.segments(of: command) {
            var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)[...]
            // Variable assignments before the program are not the program.
            while let first = words.first, first.contains("="), !first.hasPrefix("=") { words = words.dropFirst() }
            guard let first = words.first else { continue }
            let program = String(first.split(separator: "/").last ?? Substring(first))
            let phrase = words.dropFirst().first.flatMap { Self.isSubcommand($0) ? program + " " + $0 : nil } ?? program
            commands.append(Command(phrase: phrase, program: program))
        }
        let substitutes = command.contains("$(") || command.contains("`") || command.contains("<(")
        self.commands = commands
        coverable = !commands.isEmpty && !substitutes
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0).inserted }
    }

    /// The commands of a line, split at `&&`, `||`, `;`, `|`, `&` and line ends.
    private static func segments(of command: String) -> [String] {
        var segments: [String] = []
        var current = ""
        for character in command {
            if [";", "|", "&", "\n"].contains(character) {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        return segments + [current]
    }

    /// A subcommand is a plain word: letters, digits and `-`, starting with a letter; not an option, a path or a file.
    private static func isSubcommand(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter, first.isASCII else { return false }
        return word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
