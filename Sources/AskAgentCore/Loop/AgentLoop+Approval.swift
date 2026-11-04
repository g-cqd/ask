/// Hooks answering approvals in the person's place (roadmap 0192, ADR-0143).
extension AgentLoop {
    /// `context` with the hooks answering its approvals first, in order; the first answer other than `ask` wins and is kept in `answers`.
    func approving(_ context: ToolContext, _ answers: HookAnswers) -> ToolContext {
        guard !hooks.isEmpty else { return context }
        let hooks = hooks
        let clock = clock
        return context.answering { request in
            for hook in hooks {
                let fallback: ApprovalDecision = hook.failureMode == .closed ? .refuse("timed out") : .ask
                let decision = await HookDeadline.ask(
                    hook,
                    at: "approval",
                    clock: clock,
                    orElse: fallback,
                    timedOut: answers.record
                ) {
                    await hook.approval(request)
                }
                switch decision {
                    case .ask: continue
                    case .approve:
                        answers.record(.hookAnswered(hook: hook.name, tool: request.tool, approved: true))
                        return .approve
                    case .refuse(let reason):
                        answers.record(.hookAnswered(hook: hook.name, tool: request.tool, approved: false))
                        return .refuse("The hook \(hook.name) refused this call: \(reason)")
                }
            }
            return .ask
        }
    }
}
