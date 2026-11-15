public import AskAI

/// What a tool that runs a script for the model may call (ADR-0156): the run's other tools. Each call is a tool call of the
/// loop's, through its hooks and the sandbox; the loop gives this to a tool with its context, so a tool that calls others
/// holds no registry of its own.
public struct NestedTools: Sendable {
    /// The tools that can be called, as the model knows them.
    public let definitions: @Sendable () -> [ToolDefinition]
    /// Calls the tool `name` with `input`: its output, an error output when it failed or may not run.
    public let call: @Sendable (_ name: String, _ input: JSONObject) async -> ToolOutput

    public init(
        definitions: @escaping @Sendable () -> [ToolDefinition],
        call: @escaping @Sendable (_ name: String, _ input: JSONObject) async -> ToolOutput
    ) {
        self.definitions = definitions
        self.call = call
    }
}
