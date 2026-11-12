internal import AemiJSON
internal import AskAI

/// A tool call's input as a person reads it, never JSON (the owner, note n68): its keys as words in the model's order, nested values
/// indented under their label, a list of words joined and a list of records as bullets, yes and no, and empty values left out. The
/// header's one line is its scalar fields and the size of its lists; the details are left empty when that line says everything.
enum ToolProse {
    /// The call's one line: `query foo · limit 5 · 2 changes`; nil when it has nothing to say.
    static func summary(_ input: JSONObject) -> String? {
        guard case .object(let members) = root(input) else { return nil }
        let parts = members.compactMap { key, value in brief(key, value) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The call's details as labelled lines; empty when ``summary(_:)`` already says all of it on one line.
    static func details(_ input: JSONObject, fitting width: Int) -> String {
        guard let value = root(input) else { return String(decoding: input.bytes, as: UTF8.self) }
        guard case .object(let members) = value else { return lines(nil, value, indent: "").joined(separator: "\n") }
        let flat = members.values.allSatisfy(isFlat)
        if flat, let summary = summary(input), summary.count <= width { return "" }
        return members.flatMap { key, value in lines(key, value, indent: "") }.joined(separator: "\n")
    }

    private static func root(_ input: JSONObject) -> JSONValue? {
        (try? AemiJSON.parse(input.bytes)).map { JSONValue($0.root) }
    }

    /// Whether `value` reads on the one line: a word, a number, yes or no, or nothing.
    private static func isFlat(_ value: JSONValue) -> Bool {
        switch value {
            case .string(let text): !text.contains("\n")
            case .int, .number, .bool, .null: true
            case .array(let items): items.isEmpty
            case .object(let members): members.isEmpty
        }
    }

    /// `key value` for the one line: a list as its size, a record as its fields in parentheses (note n70), or its name alone.
    private static func brief(_ key: String, _ value: JSONValue) -> String? {
        switch value {
            case .array(let items) where !items.isEmpty: "\(items.count) \(words(key))"
            case .object(let members) where !members.isEmpty:
                inline(value).isEmpty ? words(key) : "\(words(key)) (\(inline(value)))"
            case .object: words(key)
            case .array, .null: nil
            case .string(let text) where text.isEmpty: nil
            default: scalar(value).map { "\(words(key)) \(TextLines.first(of: $0) ?? $0)" }
        }
    }

    /// A word, a number, yes or no; nil for a list, a record or nothing.
    private static func scalar(_ value: JSONValue) -> String? {
        switch value {
            case .string(let text): text
            case .int(let number): String(number)
            case .number(let number):
                number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
            case .bool(let flag): flag ? "yes" : "no"
            case .null, .array, .object: nil
        }
    }

    /// `Label: value`, or the label and what it holds indented under it; nothing for an empty value.
    private static func lines(_ key: String?, _ value: JSONValue, indent: String) -> [String] {
        let label = key.map { indent + capitalized(words($0)) + ":" }
        let inner = key == nil ? indent : indent + "  "
        switch value {
            case .null: return []
            case .string(let text) where text.isEmpty: return []
            case .string(let text) where text.contains("\n"):
                return (label.map { [$0] } ?? [])
                    + text.split(separator: "\n", omittingEmptySubsequences: false).map { inner + $0 }
            case .array(let items) where items.isEmpty: return []
            case .array(let items) where items.allSatisfy({ scalar($0).map { !$0.contains("\n") } ?? false }):
                let joined = items.compactMap(scalar).joined(separator: ", ")
                return [label.map { $0 + " " + joined } ?? indent + joined]
            case .array(let items):
                return (label.map { [$0] } ?? []) + items.map { inner + "- " + inline($0) }
            case .object(let members) where members.isEmpty: return []
            case .object(let members):
                return (label.map { [$0] } ?? []) + members.flatMap { lines($0.key, $0.value, indent: inner) }
            default:
                let shown = scalar(value) ?? ""
                return [label.map { $0 + " " + shown } ?? indent + shown]
        }
    }

    /// A record of a list on one line: `op add · title x`.
    private static func inline(_ value: JSONValue) -> String {
        guard case .object(let members) = value else { return scalar(value) ?? "" }
        return
            members.compactMap { key, value in
                switch value {
                    case .object(let inner): inner.isEmpty ? nil : "\(words(key)) (\(inline(value)))"
                    case .array(let items):
                        items.isEmpty ? nil : "\(words(key)) \(items.map(inline).joined(separator: ", "))"
                    default: brief(key, value)
                }
            }
            .joined(separator: " · ")
    }

    /// `timeout_seconds` and `allowWrites` as `timeout seconds` and `allow writes`.
    static func words(_ key: String) -> String {
        var words: [String] = []
        var word = ""
        for character in key {
            if character == "_" || character == "-" || character == " " {
                if !word.isEmpty { words.append(word) }
                word = ""
            } else if character.isUppercase, let last = word.last, last.isLowercase || last.isNumber {
                words.append(word)
                word = String(character)
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.lowercased() }.joined(separator: " ")
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}
