internal import AemiJSON
public import AskAI
public import Foundation

/// Compact targets/parameters and complete expanded input share the same decoded tool fields.
public enum ToolSummary {
    static let maximumCharacters = 160

    private struct Fields: Decodable {
        let command: String?
        let path: String?
        let content: String?
        let oldText: String?
        let newText: String?
        let offset: Int?
        let limit: Int?
        let job: String?
        let action: String?
        let timeoutSeconds: Int?
        let yieldSeconds: Int?
        /// The `question` tool's questions (roadmap 0117): only their words are shown.
        let questions: [Asked]?

        struct Asked: Decodable {
            let question: String?
        }

        enum CodingKeys: String, CodingKey {
            case command, path, content, offset, limit, job, action, questions
            case oldText = "old_text"
            case newText = "new_text"
            case timeoutSeconds = "timeout_seconds"
            case yieldSeconds = "yield_seconds"
        }
    }

    private static func fields(_ input: JSONObject) -> Fields? {
        try? AemiJSON.JSONDecoder().decode(Fields.self, from: input.bytes)
    }

    /// The legacy one-line command/path, retained for logs and approval questions.
    public static func line(for input: JSONObject) -> String {
        let fields = fields(input)
        return compact(fields?.command ?? fields?.path ?? asked(fields) ?? String(decoding: input.bytes, as: UTF8.self))
    }

    /// `What should change? (+1 more)`: the first of the model's questions, and how many follow.
    private static func asked(_ fields: Fields?) -> String? {
        guard let questions = fields?.questions, let first = questions.first?.question else { return nil }
        return questions.count > 1 ? "\(first) (+\(questions.count - 1) more)" : first
    }

    /// Compact target and parameters; duration/status are drawn independently by the screen. `tool` names the tool when a projection
    /// depends on it (the skill tool's `name` and `query` mean something only there).
    public static func header(for input: JSONObject, tool: String? = nil, locale: Locale = .current) -> String {
        if tool == "skill", let header = skillHeader(for: input) { return header }
        guard let fields = fields(input) else { return line(for: input) }
        var parts = [line(for: input)]
        if fields.command != nil {
            if let timeout = fields.timeoutSeconds { parts.append("timeout \(timeout)s") }
            if let yield = fields.yieldSeconds { parts.append("yield \(yield)s") }
        } else if fields.path != nil {
            if let part = pathPart(fields, locale: locale) { parts.append(part) }
        } else if let job = fields.job {
            parts = [compact(job), fields.action ?? "input"]
        }
        return parts.joined(separator: " · ")
    }

    /// What a file call does beside its path: an exact replacement, the size it writes, or the lines it reads.
    private static func pathPart(_ fields: Fields, locale: Locale) -> String? {
        if fields.oldText != nil { return "exact replacement" }
        if let content = fields.content ?? fields.newText { return formatBytes(content.utf8.count, locale: locale) }
        if let limit = fields.limit, limit > 0 {
            let first = Swift.max(1, fields.offset ?? 1)
            let end = first.addingReportingOverflow(limit - 1)
            return end.overflow ? "[\(first):]" : "[\(first):\(end.partialValue)]"
        }
        return fields.offset.map { "[\($0):]" }
    }

    /// For a tool whose input is a command, the limits the call set on it, in seconds (roadmap 0080); nil for any other tool.
    public static func commandLimits(for input: JSONObject) -> (timeout: Int?, yield: Int?)? {
        guard let fields = fields(input), fields.command != nil else { return nil }
        return (fields.timeoutSeconds, fields.yieldSeconds)
    }

    /// Complete text, never the truncated header: a command or a file's content as itself, anything else as indented JSON.
    public static func fullInput(for input: JSONObject) -> String {
        guard let fields = fields(input) else { return indented(input) }
        if let command = fields.command { return command }
        if let old = fields.oldText, let new = fields.newText { return "old_text:\n\(old)\nnew_text:\n\(new)" }
        return fields.content ?? fields.newText ?? indented(input)
    }

    /// The input as JSON indented by two spaces, keys in the model's order (roadmap 0078); its own bytes if that fails. A top-level
    /// string with a line feed is text a person reads, so it is left out of the JSON and shown after it as written, under its name.
    static func indented(_ input: JSONObject) -> String {
        guard let document = try? AemiJSON.parse(input.bytes) else {
            return String(decoding: input.bytes, as: UTF8.self)
        }
        let root = JSONValue(document.root)
        guard case .object(let members) = root else {
            return pretty(root) ?? String(decoding: input.bytes, as: UTF8.self)
        }
        var json: [String] = []
        var texts: [String] = []
        for (key, value) in members {
            if case .string(let text) = value, text.contains("\n") {
                texts.append("\(key):\n\(text)")
            } else if let name = pretty(.string(key)), let shown = pretty(value) {
                json.append("  \(name): " + shown.replacing("\n", with: "\n  "))
            } else {
                return String(decoding: input.bytes, as: UTF8.self)
            }
        }
        let object = json.isEmpty ? (texts.isEmpty ? ["{}"] : []) : ["{\n" + json.joined(separator: ",\n") + "\n}"]
        return (object + texts).joined(separator: "\n")
    }

    private static func pretty(_ value: JSONValue) -> String? {
        let options = JSONEncodingOptions(prettyPrinted: true, prettyKeySeparator: .javaScript, indent: .spaces(2))
        return (try? value.encodedBytes(options: options)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// `512 B`, or the largest IEC unit that keeps the number at least one, to one decimal at most, with the exact count:
    /// `1.5 KiB (1,536 B)`. The unit is chosen after rounding, so 1,048,575 B reads `1 MiB`, not `1024 KiB`. The decimal mark and the
    /// thousands separator are `locale`'s: `1,5 KiB (1.536 B)` in German.
    static func formatBytes(_ count: Int, locale: Locale = .current) -> String {
        guard count >= 1024 else { return "\(count) B" }
        let units = ["KiB", "MiB", "GiB", "TiB"]
        var unit = 0
        var tenths = Int((Double(count) / 1024 * 10).rounded())
        while tenths >= 10240, unit < units.count - 1 {
            unit += 1
            tenths = Int((Double(count) / Double(1 << (10 * (unit + 1))) * 10).rounded())
        }
        let decimal = locale.decimalSeparator ?? "."
        let number = "\(tenths / 10)" + (tenths % 10 == 0 ? "" : "\(decimal)\(tenths % 10)")
        let grouping = locale.groupingSeparator ?? ","
        var exact = String(count)
        var offset = exact.count - 3
        while offset > 0 {
            exact.insert(contentsOf: grouping, at: exact.index(exact.startIndex, offsetBy: offset))
            offset -= 3
        }
        return "\(number) \(units[unit]) (\(exact) B)"
    }

    static func compact(_ text: String) -> String {
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        return first.count > maximumCharacters ? String(first.prefix(maximumCharacters)) + "…" : first
    }
}
