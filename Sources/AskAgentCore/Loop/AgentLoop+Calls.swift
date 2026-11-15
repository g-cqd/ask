internal import AemiJSON

/// One tool call's way through the hooks and the tool.
extension AgentLoop {
    /// Runs one call through the hooks and the tool: each hook may rewrite or block it, then each may transform
    /// the result and add context. A blocked call never runs; its result is an error naming the reason.
    func runTool(_ original: ToolInvocation, events: (AgentEvent) -> Void) async -> (
        output: ToolOutput, contexts: [String]
    ) {
        let answers = HookAnswers()
        return await passing(original, answers: answers, events: events) { call in
            approving(context.during(call: call.id), answers).offering(nestedTools(for: call, answers))
        }
    }

    /// `original` through the hooks, then the tool in the context `context` gives for the call as the hooks left it, then the
    /// hooks again for its result. `announce` says whether the call's start is an event: a call the model made is; one made
    /// for it is not.
    func passing(
        _ original: ToolInvocation,
        announce: Bool = true,
        answers: HookAnswers,
        events: (AgentEvent) -> Void,
        in context: (ToolInvocation) -> ToolContext
    ) async -> (output: ToolOutput, contexts: [String]) {
        var call = original
        for hook in hooks {
            let current = call
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let fallback: ToolCallDecision = hook.failureMode == .closed ? .block(reason: "timed out") : .allow
            // @dl:accept -- each hook point asks its hooks the same way through HookDeadline.ask; the point, answer type and fallback are the data
            let decision = await HookDeadline.ask(
                hook,
                at: "tool.call",
                clock: clock,
                orElse: fallback,
                timedOut: events
            ) {
                await hook.toolCall(current)
            }
            switch decision {
                case .allow: continue
                case .rewrite(let input): call = ToolInvocation(id: call.id, name: call.name, input: input)
                case .block(let reason):
                    if announce { events(.toolStarted(id: call.id, name: call.name, input: call.input)) }
                    return (.error("This call was blocked before it ran: \(reason)"), [])
            }
        }
        if announce { events(.toolStarted(id: call.id, name: call.name, input: call.input)) }
        var output = await tools.run(name: call.name, input: call.input, in: context(call))
        answers.take().forEach(events)
        var contexts: [String] = []
        for hook in hooks {
            let currentCall = call
            let currentOutput = output
            let decision = await HookDeadline.ask(
                hook,
                at: "tool.result",
                clock: clock,
                orElse: ToolResultDecision(output: currentOutput),
                timedOut: events
            ) {
                await hook.toolResultDecision(currentCall, currentOutput)
            }
            output = decision.output
            if let text = decision.context, !text.allSatisfy(\.isWhitespace) {
                contexts.append("[hook \(hook.name)] \(text)")
            }
        }
        return (output, contexts)
    }
}
