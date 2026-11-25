/// What a session grant for a command line names (roadmap 0134): for each command the line runs, its program and subcommand
/// (`git status`) and the program alone (`git`). A line that can execute code its words do not plainly name is never covered
/// (security audit 2026-11-22 CRIT-04; security review 2026-11-25 N-A1):
/// - any variable assignment (`FOO=bar cmd`, `GIT_CONFIG_COUNT=1 ... git status`, `PATH=. git status`);
/// - any substitution, expansion, or redirection outside single quotes (`$(…)`, `` `…` ``, `<(…)`, `>(…)`, `$` / `${…@P}`,
///   `>`, `<`, `<<`, `<<<`);
/// - any program that runs another program or evaluates arbitrary code (``runners``), or any option that makes a program run code
///   (``runsCode``).
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
        var runsUnnamed = Self.hasUnsafeSyntax(command)
        for segment in Self.segments(of: command) {
            var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)[...]
            var hadAssignment = false
            // Leading assignments can redirect tool execution (PATH, GIT_CONFIG_*, BASH_ENV, LESSOPEN, DYLD_*): still skip
            // them to name the program for display, but never allow a session grant to cover the line (N-A1).
            while let first = words.first, Self.isAssignment(first) {
                hadAssignment = true
                words = words.dropFirst()
            }
            if hadAssignment { runsUnnamed = true }
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

    /// Whether `command` contains shell syntax that can execute unnamed code or redirect I/O outside single quotes:
    /// substitutions (`$(`, `` ` ``, `<(`, `>(`), parameter/ANSI-C expansions (`$` outside single quotes, including bash 4.4+
    /// `${x@P}` / `$'\x24(...)'`), redirections (`>`, `<`), or newlines.
    private static func hasUnsafeSyntax(_ command: String) -> Bool {
        if ["$(", "`", "<(", ">("].contains(where: { command.contains($0) }) { return true }
        let chars = Array(command)
        var i = 0
        var inSingle = false
        var inDouble = false
        while i < chars.count {
            let c = chars[i]
            if inSingle {
                if c == "'" { inSingle = false }
                i += 1
                continue
            }
            if inDouble {
                if c == "\\" {
                    i += 2
                    continue
                }
                if c == "\"" {
                    inDouble = false
                } else if c == "$" || c == "`" {
                    return true
                }
                i += 1
                continue
            }
            switch c {
                case "'": inSingle = true
                case "\"": inDouble = true
                case "\\": i += 1
                case "$", "`", ">", "<", "\n": return true
                default: break
            }
            i += 1
        }
        return inSingle || inDouble
    }

    /// Whether `word` is a shell variable assignment (`NAME=value`, `NAME+=value`), with a valid POSIX identifier prefix.
    private static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return false }
        var name = word[..<eq]
        if name.hasSuffix("+") { name = name.dropLast() }
        guard let first = name.first, first.isASCII, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// Programs that run the program named after them, or evaluate arbitrary code/scripts: a grant for one would cover anything.
    static let runners: Set<String> = Set(
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        "env xargs exec eval command builtin nohup time timeout nice sudo doas su watch parallel sh bash zsh dash ksh fish source . osascript open awk gawk mawk nawk perl python python3 ruby node make gmake ninja"
            .split(separator: " ")
            .map(String.init)
    )

    /// Whether `arguments` make `program` run code it was given (N-A1): git config/exec-path/hooks, find actions,
    /// ripgrep `--pre`, tar/zip command hooks, sed GNU `e` / `-e`/`-f`, or arbitrary package-manager script runners.
    private static func runsCode(_ program: String, _ arguments: ArraySlice<String>) -> Bool {
        switch program {
            // git's own options come before its subcommand (`git log -c` is a diff option): read until the first plain word.
            case "git":
                return arguments.prefix { $0.hasPrefix("-") || $0.contains("=") }
                    .contains {
                        $0 == "-c" || $0.hasPrefix("--config-env") || $0.hasPrefix("--exec-path")
                            || $0.hasPrefix("--upload-pack") || $0.hasPrefix("--receive-pack")
                    }
            case "find":
                return arguments.contains { ["-exec", "-execdir", "-ok", "-okdir"].contains($0) }
            case "rg", "ripgrep":
                return arguments.contains { $0 == "--pre" || $0.hasPrefix("--pre=") }
            case "tar", "gtar":
                return arguments.contains {
                    $0 == "--to-command" || $0.hasPrefix("--to-command=")
                        || $0 == "--use-compress-program" || $0.hasPrefix("--use-compress-program=")
                        || $0 == "-I" || $0 == "--checkpoint-action" || $0.hasPrefix("--checkpoint-action=")
                }
            case "zip":
                return arguments.contains { $0 == "-TT" || $0.hasPrefix("-TT") || $0 == "--unzip-command" }
            case "sed", "gsed":
                return arguments.contains { $0 == "-i" || $0.hasPrefix("-i") || $0 == "-f" || $0.hasPrefix("--file") }
            case "npm", "pnpm", "yarn", "bun":
                return arguments.first == "run" || arguments.first == "exec" || arguments.first == "x"
            case "swift":
                return arguments.first == "package" && arguments.dropFirst().first == "plugin"
            default:
                return false
        }
    }

    /// A subcommand is a plain word: letters, digits and `-`, starting with a letter; not an option, a path or a file.
    private static func isSubcommand(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter, first.isASCII else { return false }
        return word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
