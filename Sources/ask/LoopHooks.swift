internal import AskAgentCore

/// What an interactive loop asks the person through (roadmaps 0019, 0134, 0117, 0192): the sandbox's approver, the session's narrowing, a
/// server's destructive tools, the calls that change things, the model's own questions, how far a running call has got, and events
/// emitted by hooks such as `hooks.check`.
struct LoopHooks: Sendable {
    var approve: SandboxApprover?
    var narrowing: SessionNarrowing
    var destructiveApprover: DestructiveApprover?
    var callGate: ToolCallGate?
    var askPerson: PersonQuestion.Asker?
    var progress: ToolProgressReporter?
    /// Who starts the model's subagents (roadmap 0063); nil for a subagent's own loop.
    var startSubagent: SubagentTask.Starter?
    /// The tools a definition's subagent keeps (roadmap 0063 phase 3); nil keeps them all.
    var keepTools: Set<String>?
    var reportEvent: (@Sendable (AgentEvent) -> Void)?
}
