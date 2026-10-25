public import AskAI

/// A tool call the model made, as hooks see it.
// @dl:accept -- two small records of a call's parts (this and DestructiveToolCall); any such record looks alike by shape
public struct ToolInvocation: Sendable, Equatable {
    /// The call's id, which its result answers.
    public let id: String
    /// The tool the model named.
    public let name: String
    /// The input, after any earlier hook rewrote it.
    public let input: JSONObject

    /// A call with these fields.
    public init(id: String, name: String, input: JSONObject) {
        self.id = id
        self.name = name
        self.input = input
    }
}
