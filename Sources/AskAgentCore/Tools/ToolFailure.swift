/// A tool's failure, as the output the model will read.
///
/// Thrown by the helpers a tool is built from so its body can use `try` instead of switching over a `Result`.
/// ``ArgumentTool`` turns it back into an output, so nothing escapes a tool as a throw.
public struct ToolFailure: Error, Sendable, Equatable {
    public let output: ToolOutput

    /// A failure the model is told about with `message`.
    public init(_ message: String) { output = .error(message) }
}
