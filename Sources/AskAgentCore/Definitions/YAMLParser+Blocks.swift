extension YAMLParser {
    /// A `|` or `>` scalar: the lines under the key that are blank or indented more than it. A literal keeps its line breaks; a folded one joins
    /// lines with spaces and keeps a break where there is a blank line or a more-indented line. The final line breaks are dropped in every style.
    mutating func blockScalar(_ cursor: inout Int, keyIndent: Int, header: String) -> String {
        var gathered: [YAMLLine] = []
        while cursor < lines.count, lines[cursor].isBlank || lines[cursor].indent > keyIndent {
            gathered.append(lines[cursor])
            cursor += 1
        }
        let base = gathered.first { !$0.isBlank }?.indent ?? 0
        let dedented = gathered.map {
            $0.isBlank ? "" : String(repeating: " ", count: Swift.max(0, $0.indent - base)) + $0.text
        }
        let joined = header.first == "|" ? dedented.joined(separator: "\n") : Self.fold(dedented)
        var result = Substring(joined)
        while result.last == "\n" { result = result.dropLast() }
        return String(result)
    }

    private static func fold(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            if line.isEmpty {
                result += "\n"
                continue
            }
            if !result.isEmpty, !result.hasSuffix("\n") { result += line.hasPrefix(" ") ? "\n" : " " }
            result += line
        }
        return result
    }

    /// The `- item` lines at `indent`, each a scalar, an inline list or map, or a map written over the lines below the dash.
    mutating func blockList(_ cursor: inout Int, indent: Int) -> DefinitionValue {
        var items: [DefinitionValue] = []
        while cursor < lines.count {
            let line = lines[cursor]
            if line.isBlank || line.isComment {
                collectHints(from: cursor ..< cursor + 1)
                cursor += 1
                continue
            }
            guard line.isItem, line.indent == indent else { break }
            cursor += 1
            items.append(
                listItem(&cursor, dashIndent: indent, text: String(line.text.dropFirst()).trimmingWhitespace()))
        }
        return .list(items)
    }

    private mutating func listItem(_ cursor: inout Int, dashIndent: Int, text: String) -> DefinitionValue {
        let content = text.splittingComment().content
        guard let first = content.first else { return nested(&cursor, keyIndent: dashIndent) }
        if first == "[" || first == "{" || first == "\"" || first == "'" {
            return value(&cursor, keyIndent: dashIndent, rest: text)
        }
        guard let (key, rest) = Self.splitKey(content) else { return .text(content) }
        var entries = [DefinitionEntry(key: key, value: value(&cursor, keyIndent: dashIndent + 2, rest: rest))]
        if cursor < lines.count, !lines[cursor].isBlank, !lines[cursor].isItem, lines[cursor].indent > dashIndent {
            entries += mapping(&cursor, indent: lines[cursor].indent)
        }
        return .map(entries)
    }
}
