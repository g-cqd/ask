internal import AskAgentCore

/// What an interactive loop asks the person through (roadmaps 0019, 0134, 0117): the sandbox's approver, the session's narrowing, a
/// server's destructive tools, the calls that change things, and the model's own questions.
struct LoopHooks: Sendable {
    var approve: SandboxApprover?
    var narrowing: SessionNarrowing
    var destructiveApprover: DestructiveApprover?
    var callGate: ToolCallGate?
    var askPerson: PersonQuestion.Asker?
}
