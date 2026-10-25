/// One tool a definition file names, as written, and what ask makes of it.
///
/// Tools are a vocabulary per harness (`Bash`, `run_command`, `shell`), so a name ask does not know is the ordinary case and not a fault: it is
/// kept, reported as unmapped, and means nothing. A list of these can only restrict or annotate; it never adds a tool ask did not already offer.
public struct ToolReference: Sendable, Equatable {
    /// The token as written, with quotes and bullets removed.
    public let token: String
    /// The ask tool it names, or nil when ask has no tool of that name.
    public let ask: String?
    /// What was in parentheses after the name (`git diff:*` in `Bash(git diff:*)`), or nil.
    public let qualifier: String?

    public init(token: String, ask: String?, qualifier: String?) {
        self.token = token
        self.ask = ask
        self.qualifier = qualifier
    }

    /// The tool references in a field however it was written: a comma-separated or space-separated string, a list in flow or block form, or a mix.
    public static func parse(_ value: DefinitionValue?, table: ToolAliasTable = .standard) -> [ToolReference] {
        guard let value else { return [] }
        var seen = Set<String>()
        return value.scalars.flatMap(split)
            .compactMap { token in
                guard seen.insert(token).inserted else { return nil }
                let (name, qualifier) = Self.nameAndQualifier(token)
                return ToolReference(token: token, ask: table.lookup(name), qualifier: qualifier)
            }
    }

    /// Splits a scalar on commas, line breaks and whitespace that are outside parentheses, brackets and quotes, and strips bullets, quotes and
    /// the punctuation a person puts round a name.
    static func split(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        func flush() {
            let token = current.trimmingWhitespace().unquoted().trimmingBullets()
            if !token.isEmpty { tokens.append(token) }
            current = ""
        }
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
                current.append(character)
            } else if character == "(" || character == "[" || character == "{" {
                depth += 1
                current.append(character)
            } else if character == ")" || character == "]" || character == "}" {
                depth = Swift.max(0, depth - 1)
                current.append(character)
            } else if depth == 0, character == "," || character == ";" || character.isWhitespace {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
    }

    private static func nameAndQualifier(_ token: String) -> (String, String?) {
        guard let open = token.firstIndex(of: "("), token.last == ")" else { return (token, nil) }
        let qualifier = String(token[token.index(after: open)...].dropLast())
        return (String(token[..<open]), qualifier)
    }
}

extension String {
    /// The text without a leading list bullet (`-`, `*` or `•`) and without a trailing comma, so `- "read",` is `read`.
    fileprivate func trimmingBullets() -> String {
        var text = Substring(self)
        while let first = text.first, first == "-" || first == "*" || first == "•" { text = text.dropFirst() }
        while let last = text.last, last == "," || last == ";" { text = text.dropLast() }
        return String(text).trimmingWhitespace().unquoted()
    }
}
