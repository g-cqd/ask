public import AskAI

/// A call put to the person before it runs (roadmap 0134).
public struct ToolCallApproval: Sendable, Equatable {
    public let tool: String
    public let input: JSONObject
    public let scope: CallScope

    public init(tool: String, input: JSONObject, scope: CallScope) {
        self.tool = tool
        self.input = input
        self.scope = scope
    }
}
