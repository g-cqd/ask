public import AskAI

/// Code that sees each tool call before it runs and each result after, the seam extensions, approval prompts and
/// sandbox policy attach to (ADR-0025, ADR-0143, roadmap 0192).
///
/// Hooks run in the order they were given to the loop. Before a call, each sees the input as the previous one left
/// it, and the first to block ends the chain: the call does not run and the model receives an error result naming
/// the reason. After a call, each transform receives the previous one's output. Every step has a default
/// implementation, so a hook states only what it does:
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
    /// How the session and the transcript name the hook; its type's name by default.
    var name: String { get }
    /// The longest a hook call may take before it times out; nil means no deadline is enforced in-process.
    var deadline: Duration? { get }
    /// Whether a hook that misses its ``deadline`` fails open (allows) or closed (blocks).
    var failureMode: HookFailureMode { get }
    /// Called when a session opens, is resumed or is switched to (roadmap 0192).
    func sessionStart(sessionPath: String) async -> SessionStartDecision
    /// What becomes of a message from the person before it enters the conversation (roadmap 0192).
    func promptSubmit(_ text: String) async -> PromptSubmitDecision
    /// Called before each model request; may rewrite the request for that single call (roadmap 0192).
    func requestBefore(_ request: ModelRequest) async -> RequestBeforeDecision
    /// Called after each model response is recorded (roadmap 0192).
    func responseAfter(_ response: AssembledResponse) async
    /// Decides whether `call` runs, and with what input.
    func toolCall(_ call: ToolInvocation) async -> ToolCallDecision
    /// The answer to a call that would ask the person (roadmap 0192): `ask` leaves it to the next hook, then to the person.
    func approval(_ request: ToolCallApproval) async -> ApprovalDecision
    /// The result the model will see for `call`.
    func toolResult(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolOutput
    /// The result and optional conversation context for `call` (roadmap 0192); calls ``toolResult(_:_:)`` by default.
    func toolResultDecision(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolResultDecision
    /// Whether a run that would end goes on (roadmap 0192): asked after the person's follow-ups, within the continue and turn limits.
    func runStop(_ stop: RunStop) async -> RunStopDecision
    /// Whether a subagent's run that would end goes on (roadmap 0192); calls ``runStop(_:)`` by default.
    func subagentStop(_ stop: RunStop) async -> RunStopDecision
    /// Called before a compaction starts; may append instructions to the summarisation prompt (roadmap 0192).
    func compactionBefore(entries: [SessionEntry]) async -> CompactionBeforeDecision
    /// Called after a compaction finishes (roadmap 0192).
    func compactionAfter(summary: String, usage: TokenUsage) async
    /// Called when the model, thinking level or configuration changes (roadmap 0192).
    func settingsChange(_ descriptions: [String]) async
    /// Called when ask waits on the person (roadmap 0192).
    func waiting(_ reason: HookWaitingReason) async
    /// Called when ask quits or leaves the session (roadmap 0192).
    func sessionEnd(sessionPath: String) async
    /// Whether a thread starts, and on what task (roadmap 0195, `thread.start`).
    func threadStart(_ start: ThreadStart) async -> ThreadStartDecision
    /// Called before a thread's summary is written; may add to its instructions (roadmap 0195, `thread.merge`).
    func threadMerge(_ merge: ThreadMerge) async -> ThreadMergeDecision
    /// The summary a thread's parent receives (roadmap 0195, `thread.merged`).
    func threadMerged(_ merge: ThreadMerge, summary: String) async -> String
}

extension AgentHook {
    public var name: String { String(describing: type(of: self)) }
    public var deadline: Duration? { nil }
    public var failureMode: HookFailureMode { .open }
    public func sessionStart(sessionPath: String) async -> SessionStartDecision { .allow }
    public func promptSubmit(_ text: String) async -> PromptSubmitDecision { .allow }
    public func requestBefore(_ request: ModelRequest) async -> RequestBeforeDecision { .allow }
    public func responseAfter(_ response: AssembledResponse) async {}
    public func toolCall(_ call: ToolInvocation) async -> ToolCallDecision { .allow }
    public func approval(_ request: ToolCallApproval) async -> ApprovalDecision { .ask }
    public func toolResult(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolOutput { output }
    public func toolResultDecision(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolResultDecision {
        ToolResultDecision(output: await toolResult(call, output))
    }
    public func runStop(_ stop: RunStop) async -> RunStopDecision { .stop }
    public func subagentStop(_ stop: RunStop) async -> RunStopDecision { await runStop(stop) }
    public func compactionBefore(entries: [SessionEntry]) async -> CompactionBeforeDecision { .allow }
    public func compactionAfter(summary: String, usage: TokenUsage) async {}
    public func settingsChange(_ descriptions: [String]) async {}
    public func waiting(_ reason: HookWaitingReason) async {}
    public func sessionEnd(sessionPath: String) async {}
    public func threadStart(_ start: ThreadStart) async -> ThreadStartDecision { .allow }
    public func threadMerge(_ merge: ThreadMerge) async -> ThreadMergeDecision { .allow }
    public func threadMerged(_ merge: ThreadMerge, summary: String) async -> String { summary }
}
