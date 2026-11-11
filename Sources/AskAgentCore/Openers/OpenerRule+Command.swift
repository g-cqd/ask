/// What a rule's command may be (roadmap 0216, ADR-0148), checked when the configuration is read, so a rule that could not be run
/// safely is refused by name before any click reaches it.
extension OpenerRule {
    /// The placeholders a command's arguments may hold.
    public static let placeholders = ["{path}", "{line}", "{column}", "{url}"]

    /// Why `command` cannot be a rule's command, or nil when it can.
    ///
    /// - The program is the person's choice alone: a placeholder in it would let a link name what runs.
    /// - A `{word}` that is no placeholder is refused, since it would reach the program as written, which is never what was meant.
    /// - A control character is refused: the command is shown before it runs, and what is shown must be what runs.
    public static func problem(in command: [String]) -> String? {
        guard let program = command.first, !program.isEmpty else {
            return "needs a program to run, as its first argument"
        }
        if placeholders.contains(where: program.contains) {
            return "names its program with a placeholder: the program is yours to choose, not the link's"
        }
        for argument in command {
            if argument.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F ... 0x9F).contains($0.value) }) {
                return "holds a control character"
            }
            if let unknown = unknownPlaceholder(in: argument) {
                return "holds \(unknown), which is not a placeholder: they are \(placeholders.joined(separator: ", "))"
            }
        }
        return nil
    }

    /// The first `{word}` of letters in `argument` that is not a placeholder.
    private static func unknownPlaceholder(in argument: String) -> String? {
        var rest = Substring(argument)
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            let word = after.prefix { $0.isLetter }
            if !word.isEmpty, after.dropFirst(word.count).first == "}" {
                let whole = "{" + word + "}"
                if !placeholders.contains(whole) { return whole }
            }
            rest = after
        }
        return nil
    }

    /// What the rule matches, in words, for the question and the list of what was allowed.
    public var matchDescription: String {
        var words =
            switch kind {
                case .file?: "files"
                case .folder?: "folders"
                case .web?: "web links"
                case nil: extensions == nil ? "links" : "files"
            }
        if let extensions, !extensions.isEmpty {
            words += " ending " + extensions.map { "." + $0 }.joined(separator: " or ")
        }
        if let host { words += " at " + host }
        if let pattern { words += " matching " + pattern }
        return words == "links" ? "every link" : words
    }
}
