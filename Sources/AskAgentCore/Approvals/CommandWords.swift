/// What a session grant for a command line names (roadmap 0134): for each command the line runs, its program and subcommand
/// (`git status`) and the program alone (`git`). A line that runs a command its words do not name is never covered (security audit
/// 2026-11-22, CRIT-04): a substitution (`$(…)`, a backquote, `<(…)`, `>(…)`), a program that runs the program after it (``runners``),
/// or an option that makes a program run code (``runsCode``).
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
        var runsUnnamed = ["$(", "`", "<(", ">("].contains { command.contains($0) }
        for segment in Self.segments(of: command) {
            var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)[...]
            // Variable assignments before the program are not the program.
            while let first = words.first, first.contains("="), !first.hasPrefix("=") { words = words.dropFirst() }
            guard let first = words.first else { continue }
            let program = String(first.split(separator: "/").last ?? Substring(first))
            let phrase = words.dropFirst().first.flatMap { Self.isSubcommand($0) ? program + " " + $0 : nil } ?? program
            commands.append(Command(phrase: phrase, program: program))
            if Self.runners.contains(program) || Self.runsCode(program, words.dropFirst()) { runsUnnamed = true }
        }
        self.commands = commands
        coverable = !commands.isEmpty && !runsUnnamed
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0).inserted }
    }

    /// The commands of a line, split at `&&`, `||`, `;`, `|`, `&` and line ends, outside quotes and heredoc bodies.
    // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
    private static func segments(of command: String) -> [String] { ShellSegments.split(command) }

    /// Programs that run the program named after them, or whatever text they are given: a grant for one would cover anything.
    static let runners: Set<String> = [
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        "env", "xargs", "exec", "eval", "command", "builtin", "nohup", "time", "timeout", "nice", "sudo", "doas", "su",
        "watch",
        "parallel", "sh", "bash", "zsh", "dash", "ksh", "fish", "source", ".", "osascript", "open"
    ]

    /// Whether `arguments` make `program` run code it was given: git's configuration on the command line (its pager, hooks and
    /// aliases run programs) or another exec path, and find's actions.
    private static func runsCode(_ program: String, _ arguments: ArraySlice<String>) -> Bool {
        switch program {
            // git's own options come before its subcommand (`git log -c` is a diff option): read until the first plain word.
            case "git":
                arguments.prefix { $0.hasPrefix("-") || $0.contains("=") }
                    .contains { $0 == "-c" || $0.hasPrefix("--config-env") || $0.hasPrefix("--exec-path") }
            case "find": arguments.contains { ["-exec", "-execdir", "-ok", "-okdir"].contains($0) }
            default: false
        }
    }

    /// A subcommand is a plain word: letters, digits and `-`, starting with a letter; not an option, a path or a file.
    private static func isSubcommand(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter, first.isASCII else { return false }
        return word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
