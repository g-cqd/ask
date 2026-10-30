/// What the person allowed for the session (roadmap 0134): subcommands (`git status`), programs (`git`), files, and other tools. A
/// command line is covered only when every command it runs is, and never when it holds a substitution.
public struct CallGrants: Sendable, Equatable {
    private var phrases: Set<String> = []
    private var programs: Set<String> = []
    private var files: Set<String> = []
    private var tools: Set<String> = []

    public init() {}

    /// Remembers what an "Allow for the session" answer to a question about `scope` allows.
    public mutating func grant(_ scope: CallScope) {
        switch scope {
            case .command(let words): phrases.formUnion(words.phrases)
            case .file(let path): files.insert(path)
            case .tool(let name): tools.insert(name)
        }
    }

    /// Remembers an "Allow the program for the session" answer.
    public mutating func grantPrograms(_ words: CommandWords) { programs.formUnion(words.programs) }

    /// Whether a call about `scope` needs no question.
    public func covers(_ scope: CallScope) -> Bool {
        switch scope {
            case .command(let words):
                guard words.coverable else { return false }
                return words.commands.allSatisfy { phrases.contains($0.phrase) || programs.contains($0.program) }
            case .file(let path): return files.contains(path)
            case .tool(let name): return tools.contains(name)
        }
    }
}
