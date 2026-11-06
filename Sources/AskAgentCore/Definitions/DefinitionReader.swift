internal import AemiFrontMatter
internal import AemiHMMMLCore
internal import AemiTOML
internal import AemiYAML

/// Reads a definition file's head with AemiHMMML's parsers (roadmap 0109): located by its front matter rules, parsed as YAML or
/// TOML in recovering mode, so nothing is ever rejected and what was repaired is said. The values become ``DefinitionValue``s: a
/// scalar as the text it was written as, a list, or a map in written order.
enum DefinitionReader {
    /// What the head of a definition file says.
    typealias Read = (entries: [DefinitionEntry], hints: [DefinitionEntry], notes: [String])

    /// A head as real harness files write one: YAML or TOML fences, blank lines before them, and a head that never closes read up
    /// to its first blank line.
    static let headOptions = FrontMatterOptions(
        formats: [.yaml, .toml],
        leadingBlankLines: true,
        unclosedEndsAtBlankLine: true
    )

    /// Nesting and aliases bounded for heads, far past what a real one holds (ADR-0092's 32 flow and 48 indentation levels).
    static let limits = MarkupLimits(depth: 48, aliases: 1_000, aliasExpansion: 10_000)

    /// The head at `head` in `bytes`.
    static func read(_ head: FrontMatter, in bytes: [UInt8]) -> Read {
        // Recovering never throws.
        guard let reading = try? head.read(from: bytes, policy: .recovering, limits: limits, recordsComments: true)
        else {
            return ([], [], [])
        }
        var notes = notes(reading.diagnostics, in: bytes)
        switch reading.value {
            case .yaml(let document):
                let root = document.root
                var entries: [DefinitionEntry] = []
                if root.kind == .mapping {
                    entries = root.entries.map {
                        DefinitionEntry(key: key($0.key, bytes), value: yaml($0.value, bytes))
                    }
                } else if !root.isNull {
                    notes.append("the head is not `key: value` lines and was skipped")
                }
                return (entries, hints(document.comments, in: bytes), notes)
            case .toml(let document):
                return (flattened(document.root, bytes), hints(document.comments, in: bytes), notes)
            case .json, nil:
                return ([], [], notes)
        }
    }

    /// A whole TOML file, as Codex's and Vibe's agent definitions are.
    static func toml(_ bytes: [UInt8]) -> Read {
        let options = TOMLOptions(policy: .recovering, limits: limits, recordsComments: true)
        guard let document = try? TOMLDocument(parsing: bytes, options: options) else { return ([], [], []) }
        return (
            flattened(document.root, bytes), hints(document.comments, in: bytes), notes(document.diagnostics, in: bytes)
        )
    }

    /// A value written in a comment (`# fallback_models: [a, b]`): a flow list when it reads as one, with a note after it left out
    /// (`[flash_lite, flash] (effort: low)`); its text otherwise.
    static func flow(_ text: String) -> DefinitionValue {
        let options = YAMLOptions(limits: limits)
        // The longest part that ends at a `]` and is a list: few candidates, each read once, in a comment's length.
        for close in text.indices.reversed() where text[close] == "]" {
            let candidate = String(text[...close])
            if let document = try? YAMLDocument(parsing: candidate, options: options), document.root.kind == .sequence {
                return yaml(document.root, Array(candidate.utf8))
            }
        }
        return .text(text)
    }

    // MARK: Values

    private static func yaml(_ value: YAMLValue, _ bytes: [UInt8]) -> DefinitionValue {
        DefinitionBuilder.build(value) { node in
            switch node.kind {
                case .scalar: .text(text(node))
                case .sequence: .list(node.elements)
                case .mapping: .map(node.entries.map { (key: key($0.key, bytes), value: $0.value) })
            }
        }
    }

    /// A scalar's text; a block scalar's final line break is not part of what it says.
    private static func text(_ scalar: YAMLValue) -> String {
        var text = scalar.text ?? ""
        if scalar.scalarStyle == .literal || scalar.scalarStyle == .folded {
            while text.last == "\n" { text.removeLast() }
        }
        return text
    }

    /// A key's text; a list or map used as a key (rare, and legal YAML) as it was written.
    private static func key(_ key: YAMLValue, _ bytes: [UInt8]) -> String {
        guard case .scalar = key.kind else { return String(decoding: bytes[key.sourceRange], as: UTF8.self) }
        return text(key)
    }

    private static func toml(_ value: TOMLValue, _ bytes: [UInt8]) -> DefinitionValue {
        DefinitionBuilder.build(value) { node in
            switch node.kind {
                case .table: .map(node.entries)
                case .array: .list(node.elements)
                // Numbers, booleans and dates as they were written.
                case .string: .text(node.string ?? "")
                default: .text(String(decoding: bytes[node.sourceRange], as: UTF8.self))
            }
        }
    }

    /// The root table's keys, with each table a `[header]` or a dotted key made as a prefix on the keys under it (`limits.turns`);
    /// an inline table is a map.
    private static func flattened(_ root: TOMLValue, _ bytes: [UInt8]) -> [DefinitionEntry] {
        var entries: [DefinitionEntry] = []
        var stack: [(prefix: String, members: [(key: String, value: TOMLValue)], next: Int)] = [("", root.entries, 0)]
        while let top = stack.indices.last {
            guard stack[top].next < stack[top].members.count else {
                stack.removeLast()
                continue
            }
            let (key, value) = stack[top].members[stack[top].next]
            stack[top].next += 1
            let name = stack[top].prefix + key
            if value.kind == .table, !value.isInline {
                stack.append((name + ".", value.entries, 0))
            } else {
                entries.append(DefinitionEntry(key: name, value: toml(value, bytes)))
            }
        }
        return entries
    }

    // MARK: Comments and notes

    private static func hints(_ comments: [Range<Int>], in bytes: [UInt8]) -> [DefinitionEntry] {
        comments.compactMap { comment in
            DefinitionFile.hint(
                fromComment: String(decoding: bytes[(comment.lowerBound + 1) ..< comment.upperBound], as: UTF8.self)
            )
        }
    }

    /// What was repaired, one sentence each, with its line.
    private static func notes(_ diagnostics: Diagnostics, in bytes: [UInt8]) -> [String] {
        var notes = diagnostics.recorded.map { diagnostic in
            let range = min(diagnostic.range.lowerBound, bytes.count) ..< min(diagnostic.range.upperBound, bytes.count)
            // A key written twice is the one repair a reader of definitions meets often: said as ask always said it.
            if diagnostic.code == .yamlDuplicateKey || diagnostic.code == .tomlDuplicateKey {
                return
                    "the key `\(String(decoding: bytes[range], as: UTF8.self))` is written twice; the last value is used"
            }
            let line = bytes[..<range.lowerBound].count { $0 == 0x0A } + 1
            return "line \(line): \(diagnostic.message)"
        }
        if diagnostics.dropped > 0 { notes.append("and \(diagnostics.dropped) more") }
        return notes
    }
}
