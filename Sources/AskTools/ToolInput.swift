internal import AemiJSON
internal import AskAI

/// A tool call's input read once: its fields by name, and the one a tool cannot run without.
struct ToolInput {
    let root: JSON?

    init(_ input: JSONObject) { root = (try? AemiJSON.parse(input.bytes))?.root }

    /// The non-empty string `key` holds, or nil.
    func text(_ key: String) -> String? { root?[key].string.flatMap { $0.isEmpty ? nil : $0 } }
}
