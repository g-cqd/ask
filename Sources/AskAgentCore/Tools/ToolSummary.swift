internal import AemiJSON
public import AskAI

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

        enum CodingKeys: String, CodingKey {
            case command, path, content, offset, limit, job, action
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
        return compact(fields?.command ?? fields?.path ?? String(decoding: input.bytes, as: UTF8.self))
    }

    /// Compact target and parameters; duration/status are drawn independently by the screen.
    public static func header(for input: JSONObject) -> String {
        guard let fields = fields(input) else { return line(for: input) }
        var parts = [line(for: input)]
        if fields.command != nil {
            if let timeout = fields.timeoutSeconds { parts.append("timeout \(timeout)s") }
            if let yield = fields.yieldSeconds { parts.append("yield \(yield)s") }
        } else if fields.path != nil {
            if fields.oldText != nil {
                parts.append("exact replacement")
            } else if let content = fields.content ?? fields.newText {
                parts.append(formatBytes(content.utf8.count))
            } else if let limit = fields.limit, limit > 0 {
                let first = Swift.max(1, fields.offset ?? 1)
                let end = first.addingReportingOverflow(limit - 1)
                parts.append(end.overflow ? "[\(first):]" : "[\(first):\(end.partialValue)]")
            } else if let offset = fields.offset {
                parts.append("[\(offset):]")
            }
        } else if let job = fields.job {
            parts = [compact(job), fields.action ?? "input"]
        }
        return parts.joined(separator: " · ")
    }

    /// For a tool whose input is a command, the limits the call set on it, in seconds (roadmap 0080); nil for any other tool.
    public static func commandLimits(for input: JSONObject) -> (timeout: Int?, yield: Int?)? {
        guard let fields = fields(input), fields.command != nil else { return nil }
        return (fields.timeoutSeconds, fields.yieldSeconds)
    }

    /// Complete text, never the truncated header. Unknown tools retain their original JSON bytes.
    public static func fullInput(for input: JSONObject) -> String {
        guard let fields = fields(input) else { return String(decoding: input.bytes, as: UTF8.self) }
        if let command = fields.command { return command }
        if let old = fields.oldText, let new = fields.newText { return "old_text:\n\(old)\nnew_text:\n\(new)" }
        return fields.content ?? fields.newText ?? String(decoding: input.bytes, as: UTF8.self)
    }

    static func formatBytes(_ count: Int) -> String {
        guard count >= 1024 else { return "\(count) B" }
        let kib = Double(count) / 1024.0
        let tenths = Int((kib * 10).rounded())
        let formattedKib = "\(tenths / 10)" + (tenths % 10 == 0 ? "" : ".\(tenths % 10)")
        var exact = String(count)
        var offset = exact.count - 3
        while offset > 0 {
            exact.insert(",", at: exact.index(exact.startIndex, offsetBy: offset))
            offset -= 3
        }
        return "\(formattedKib) KiB (\(exact) B)"
    }

    private static func compact(_ text: String) -> String {
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        return first.count > maximumCharacters ? String(first.prefix(maximumCharacters)) + "…" : first
    }
}
