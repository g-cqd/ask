internal import Foundation

/// A TOML head, or a whole TOML file such as Codex's and Vibe's agent definitions, read for its `key = value` lines.
///
/// Strings in every form (basic, literal, and both multi-line forms), arrays and inline tables across lines, numbers and booleans as the text
/// they were written as, and `[table]` headers as a prefix on the keys under them. It never fails; a line it cannot read is skipped and noted.
struct TOMLHead {
    private(set) var entries: [DefinitionEntry] = []
    private(set) var hints: [DefinitionEntry] = []
    private(set) var diagnostics: [String] = []
    private let lines: [String]
    private var cursor = 0

    init(lines: [String]) {
        self.lines = lines
        var table = ""
        var positions: [String: Int] = [:]
        while cursor < lines.count {
            let text = lines[cursor].trimmingWhitespace()
            cursor += 1
            if text.isEmpty { continue }
            if text.first == "#" {
                if let hint = DefinitionFile.hint(fromComment: String(text.dropFirst())) { hints.append(hint) }
                continue
            }
            if text.first == "[", text.last == "]", !text.contains("=") {
                table = text.trimming(["[", "]", " "])
                continue
            }
            guard let (key, rest) = Self.splitAssignment(text) else {
                diagnostics.append("line \(cursor) is not `key = value` and was skipped")
                continue
            }
            let value = self.value(rest)
            let name = table.isEmpty ? key : table + "." + key
            if let existing = positions[name.canonicalKey] {
                diagnostics.append("the key `\(name)` is written twice; the last value is used")
                entries[existing] = DefinitionEntry(key: name, value: value)
            } else {
                positions[name.canonicalKey] = entries.count
                entries.append(DefinitionEntry(key: name, value: value))
            }
        }
    }

    /// `key = rest`, with the key bare or quoted.
    private static func splitAssignment(_ text: String) -> (String, String)? {
        text.splittingKey(at: "=", needsSpaceAfter: false)
    }

    private mutating func value(_ rest: String) -> DefinitionValue {
        if rest.hasPrefix("\"\"\"") { return .text(multiline(rest, delimiter: "\"\"\"", escapes: true)) }
        if rest.hasPrefix("'''") { return .text(multiline(rest, delimiter: "'''", escapes: false)) }
        let (content, comment) = rest.splittingComment()
        if let comment, let hint = DefinitionFile.hint(fromComment: comment) { hints.append(hint) }
        guard let first = content.first else { return .text("") }
        if first == "[" || first == "{" { return gathered(content) }
        return FlowParser.parse(content)
    }

    /// An array or inline table that may run over several lines, with comments inside it dropped.
    private mutating func gathered(_ first: String) -> DefinitionValue {
        var text = first
        var count = 0
        while !YAMLParser.isBalanced(text), cursor < lines.count, count < YAMLParser.gatherLimit {
            text += " " + lines[cursor].trimmingWhitespace().splittingComment().content
            cursor += 1
            count += 1
        }
        return FlowParser.parse(text)
    }

    /// A `"""` or `'''` string: everything up to the closing delimiter, with the first line break dropped.
    private mutating func multiline(_ rest: String, delimiter: String, escapes: Bool) -> String {
        var text = String(rest.dropFirst(3))
        var count = 0
        while !text.contains(delimiter), cursor < lines.count, count < YAMLParser.gatherLimit {
            text += "\n" + lines[cursor]
            cursor += 1
            count += 1
        }
        if let close = text.range(of: delimiter) { text = String(text[..<close.lowerBound]) }
        if text.first == "\n" { text.removeFirst() }
        return escapes
            ? text.replacing("\\n", with: "\n").replacing("\\\"", with: "\"").replacing("\\\\", with: "\\") : text
    }
}
