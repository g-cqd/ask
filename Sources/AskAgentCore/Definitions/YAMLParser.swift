struct YAMLParser {
    let lines: [YAMLLine]
    var entries: [DefinitionEntry] = []
    var hints: [DefinitionEntry] = []
    var diagnostics: [String] = []
    var depth = 0
    /// How deep maps and lists may nest by indentation; deeper lines are skipped with a note, so a file cannot exhaust the stack.
    static let maximumDepth = 48
    /// The most lines one value may gather (a flow collection or a quoted scalar that never closes must not eat the file).
    static let gatherLimit = 400

    init(lines: [String]) { self.lines = lines.map(YAMLLine.init) }

    mutating func run() {
        var cursor = 0
        guard let first = lines.firstIndex(where: { !$0.isBlank && !$0.isComment }) else {
            collectHints(from: 0 ..< lines.count)
            return
        }
        collectHints(from: 0 ..< first)
        cursor = first
        entries = mapping(&cursor, indent: lines[first].indent)
        if cursor < lines.count {
            diagnostics.append("line \(cursor + 1) of the head could not be placed and was skipped")
        }
    }

    mutating func collectHints(from range: Range<Int>) {
        for index in range where lines[index].isComment {
            if let hint = DefinitionFile.hint(fromComment: String(lines[index].text.dropFirst())) { hints.append(hint) }
        }
    }

    /// The keys at `indent`, from `cursor` until a line that is less indented. Lines it cannot read are skipped, not fatal.
    mutating func mapping(_ cursor: inout Int, indent: Int) -> [DefinitionEntry] {
        var found: [DefinitionEntry] = []
        var positions: [String: Int] = [:]
        while cursor < lines.count {
            let line = lines[cursor]
            if line.isBlank {
                cursor += 1
                continue
            }
            if line.isComment {
                collectHints(from: cursor ..< cursor + 1)
                cursor += 1
                continue
            }
            if line.indent < indent { break }
            guard !line.isItem, let (key, rest) = Self.splitKey(line.text) else {
                diagnostics.append("line \(cursor + 1) of the head is not `key: value` and was skipped")
                cursor += 1
                continue
            }
            cursor += 1
            let value = self.value(&cursor, keyIndent: line.indent, rest: rest)
            let canonical = key.canonicalKey
            if let existing = positions[canonical] {
                diagnostics.append("the key `\(key)` is written twice; the last value is used")
                found[existing] = DefinitionEntry(key: key, value: value)
            } else {
                positions[canonical] = found.count
                found.append(DefinitionEntry(key: key, value: value))
            }
        }
        return found
    }

    /// Splits `key: rest`, where the key may be quoted and the colon is followed by a space or the end of the line.
    static func splitKey(_ text: String) -> (key: String, rest: String)? {
        text.splittingKey(at: ":", needsSpaceAfter: true)
    }
}
