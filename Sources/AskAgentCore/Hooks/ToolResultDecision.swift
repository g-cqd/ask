/// What a hook returns after a tool call finishes (roadmap 0192, ADR-0143): the output the model sees, and optional context added to
/// the conversation as a labelled user entry.
public struct ToolResultDecision: Sendable, Equatable {
    public var output: ToolOutput
    public var context: String?

    public init(output: ToolOutput, context: String? = nil) {
        self.output = output
        self.context = context
    }
}
