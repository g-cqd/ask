internal import AemiJSON
public import AskAI

/// A tool whose input is one `Decodable` value.
///
/// Every tool decoded its input, answered a malformed one with the same error, and only then did its work. That
/// preamble is the template here, not the tool's: a tool states its `Arguments` and what it does with them.
///
/// ```swift
/// struct Echo: ArgumentTool {
///     struct Arguments: Decodable, Sendable { let text: String }
///     let definition = ToolDefinition(name: "echo", description: "Echo text.", inputSchema: …)
///     func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
///         ToolOutput(arguments.text)
///     }
/// }
/// ```
public protocol ArgumentTool: Tool {
    associatedtype Arguments: Decodable & Sendable

    /// Does the tool's work. A failure the model should read is thrown as a ``ToolFailure``.
    func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput
}

extension ArgumentTool {
    /// Decodes `input`, then runs the tool.
    /// - Returns: the tool's output; or an error output naming the tool, as the model knows it, and the problem
    ///   when the input does not decode; or the output of a thrown ``ToolFailure``.
    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let arguments: Arguments
        do {
            arguments = try AemiJSON.JSONDecoder().decode(Arguments.self, from: input.bytes)
        } catch {
            return .error("Invalid arguments for \(definition.name): \(error)")
        }
        do {
            return try await run(arguments, in: context)
        } catch {
            return error.output
        }
    }
}
