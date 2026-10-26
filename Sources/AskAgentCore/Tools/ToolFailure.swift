/// A tool's failure, as the output the model will read.
///
/// Thrown by the helpers a tool is built from so its body can use `try` instead of switching over a `Result`.
/// ``ArgumentTool`` turns it back into an output, so nothing escapes a tool as a throw.
public struct ToolFailure: Error, Sendable, Equatable {
    public let output: ToolOutput

    /// A failure the model is told about with `message`.
    public init(_ message: String) { output = .error(message) }

    /// A refusal that says only what was refused: the path as the model gave it. Which rule refused it, what else is protected and who
    /// could change it stay with the user (ADR-0115): the model gets the least that lets it stop trying.
    public static func notPermitted(_ path: String) -> ToolFailure { ToolFailure("Not permitted: \(path).") }
}
