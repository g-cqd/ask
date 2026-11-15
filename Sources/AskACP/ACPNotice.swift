internal import AemiJSON

/// A notice as ACP shows it (ACP v1, Prompt Turn, "Session notices"): something for the person to see now, which is no part of
/// the conversation. Its title is the notice's first line and its description the rest.
enum ACPNotice {
    /// The `notice` update for `text`, or nil when it says nothing: a title may not be empty.
    static func update(_ text: String, isError: Bool) -> JSONValue? {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard let title = lines.first.map({ $0.trimmingPrefix(while: \.isWhitespace) }), !title.isEmpty else {
            return nil
        }
        var update: OrderedDictionary<String, JSONValue> = [
            "sessionUpdate": "notice", "severity": isError ? "error" : "info", "title": .string(String(title))
        ]
        if lines.count > 1 { update["description"] = .string(String(lines[1])) }
        return .object(update)
    }
}
