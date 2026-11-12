internal import AemiJSON
public import AskAI
public import Foundation

/// Compact targets/parameters and complete expanded input share the same decoded tool fields.
public enum ToolSummary {
    static let maximumCharacters = 160

    struct Fields: Decodable {
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
            let header: String?
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

    static func fields(_ input: JSONObject) -> Fields? {
        try? AemiJSON.JSONDecoder().decode(Fields.self, from: input.bytes)
    }

    /// The legacy one-line command/path, retained for logs and approval questions.
    public static func line(for input: JSONObject) -> String { line(fields(input), input) }

    static func line(_ fields: Fields?, _ input: JSONObject) -> String {
        // Never the input's JSON (note n68): what it says, in words.
        compact(fields?.command ?? fields?.path ?? asked(fields) ?? ToolProse.summary(input) ?? "")
    }

    /// `What should change? (+1 more)`: the first of the model's questions, and how many follow.
    private static func asked(_ fields: Fields?) -> String? {
        guard let questions = fields?.questions, let first = questions.first?.question else { return nil }
        return questions.count > 1 ? "\(first) (+\(questions.count - 1) more)" : first
    }

    /// Compact parameters, then the target: modifiers before the subject (the owner's choice, 2026-11-02, roadmap 0080), so a long
    /// path or command cut at the edge never hides them. Duration and status are drawn by the screen. `tool` names the tool when a
    /// projection depends on it (the skill tool's `name` and `query` mean something only there).
    public static func header(for input: JSONObject, tool: String? = nil, locale: Locale = .current) -> String {
        header(fields(input), input, tool: tool, locale: locale)
    }

    static func header(_ fields: Fields?, _ input: JSONObject, tool: String?, locale: Locale) -> String {
        if tool == "skill", let header = skillHeader(for: input) { return header }
        guard let fields else { return line(nil, input) }
        var parts: [String] = []
        if fields.command != nil {
            if let timeout = fields.timeoutSeconds { parts.append("timeout \(timeout)s") }
            if let yield = fields.yieldSeconds { parts.append("yield \(yield)s") }
        } else if fields.path != nil {
            if let part = pathPart(fields, locale: locale) { parts.append(part) }
        } else if let job = fields.job {
            return [fields.action ?? "input", compact(job)].joined(separator: " · ")
        }
        return (parts + [line(fields, input)]).joined(separator: " · ")
    }

    /// What a file call does beside its path: an exact replacement, the size it writes, or the lines it reads.
    private static func pathPart(_ fields: Fields, locale: Locale) -> String? {
        if fields.oldText != nil { return "exact replacement" }
        if let content = fields.content ?? fields.newText { return formatBytes(content.utf8.count, locale: locale) }
        if let limit = fields.limit, limit > 0 {
            let first = Swift.max(1, fields.offset ?? 1)
            let end = first.addingReportingOverflow(limit - 1)
            if end.overflow { return "from line \(first)" }
            return end.partialValue == first ? "line \(first)" : "lines \(first)–\(end.partialValue)"
        }
        return fields.offset.map { "from line \($0)" }
    }

    /// For a tool whose input is a command, the limits the call set on it, in seconds (roadmap 0080); nil for any other tool.
    public static func commandLimits(for input: JSONObject) -> (timeout: Int?, yield: Int?)? {
        guard let fields = fields(input), fields.command != nil else { return nil }
        return (fields.timeoutSeconds, fields.yieldSeconds)
    }

    /// The file the call names, as the model wrote it; nil for a call that names none.
    public static func path(for input: JSONObject) -> String? { fields(input)?.path }

    /// Complete text, never the truncated header: a command or a file's content as itself, the questions asked in words, anything
    /// else as labelled lines (note n68); empty when the header says it all.
    public static func fullInput(for input: JSONObject) -> String { fullInput(fields(input), input) }

    static func fullInput(_ fields: Fields?, _ input: JSONObject) -> String {
        guard let fields else { return ToolProse.details(input, fitting: maximumCharacters) }
        if let command = fields.command { return command }
        if let old = fields.oldText, let new = fields.newText { return EditDiff.text(old: old, new: new) }
        if let questions = fields.questions {
            return
                questions.compactMap { asked in
                    asked.question.map { question in asked.header.map { "\($0): \(question)" } ?? question }
                }
                .joined(separator: "\n")
        }
        return fields.content ?? fields.newText ?? ToolProse.details(input, fitting: maximumCharacters)
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
        let first = TextLines.first(of: text) ?? text
        return first.count > maximumCharacters ? String(first.prefix(maximumCharacters)) + "…" : first
    }
}
