internal import AemiJSON
internal import AskAI

/// What a tool returns. A failure is an output too: the model reads it and decides what to do next.
public struct ToolOutput: Sendable, Equatable {
    public var content: String
    public var isError: Bool

    /// An output with this content.
    public init(_ content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// A failed outcome, explained for the model.
    public static func error(_ content: String) -> ToolOutput { ToolOutput(content, isError: true) }
}
