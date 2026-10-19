/// Code that sees each tool call before it runs and each result after, the seam extensions, approval prompts and
/// sandbox policy attach to (ADR-0025).
///
/// Hooks run in the order they were given to the loop. Before a call, each sees the input as the previous one left
/// it, and the first to block ends the chain: the call does not run and the model receives an error result naming
/// the reason. After a call, each transform receives the previous one's output. Both steps have default
/// implementations, so a hook states only what it does:
///
/// ```swift
/// struct NoForcePush: AgentHook {
///     func toolCall(_ call: ToolInvocation) async -> ToolCallDecision {
///         call.name == "bash" && String(decoding: call.input.bytes, as: UTF8.self).contains("push --force")
///             ? .block(reason: "force pushes are not allowed") : .allow
///     }
/// }
/// ```
public protocol AgentHook: Sendable {
    /// Decides whether `call` runs, and with what input.
    func toolCall(_ call: ToolInvocation) async -> ToolCallDecision
    /// The result the model will see for `call`.
    func toolResult(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolOutput
}

extension AgentHook {
    public func toolCall(_ call: ToolInvocation) async -> ToolCallDecision { .allow }
    public func toolResult(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolOutput { output }
}
