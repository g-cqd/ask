public import AskAI

/// A capability the model can call. Implementations live in AskTools; the loop owns this contract.
///
/// `run` never throws: every outcome, including a failure, is an output. It should return promptly when its
/// task is cancelled.
public protocol Tool: Sendable {
    var definition: ToolDefinition { get }
    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput
}
