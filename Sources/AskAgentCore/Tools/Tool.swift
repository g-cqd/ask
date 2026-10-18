internal import AemiJSON
public import AskAI

/// A capability the model can call. Implementations live in AskTools; the loop owns this contract.
///
/// `run` never throws: every outcome, including a failure, is an output. It should return promptly when its
/// task is cancelled.
public protocol Tool: Sendable {
    var definition: ToolDefinition { get }
    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput
}

extension Tool {
    /// Decodes `input` into the tool's arguments.
    /// - Returns: the arguments, or an error output naming the tool, as the model knows it, and the problem.
    public func arguments<Value: Decodable>(_ type: Value.Type, from input: JSONObject) -> ToolArguments<Value> {
        do {
            return .success(try AemiJSON.JSONDecoder().decode(Value.self, from: input.bytes))
        } catch {
            return .failure(.error("Invalid arguments for \(definition.name): \(error)"))
        }
    }
}
