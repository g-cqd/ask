internal import AskAI

/// The calls a tool makes for the model (ADR-0156).
extension AgentLoop {
    /// What the call `outer` may call: every other tool of the run. A nested call passes the hooks as a call of the model's
    /// does, and runs in `outer`'s context as a script's call (``ToolContext/withinScript()``). Its start is not an event and
    /// it is not recorded: the model made one call, and reads one result.
    func nestedTools(for outer: ToolInvocation, _ answers: HookAnswers) -> NestedTools {
        let loop = self
        return NestedTools(
            definitions: { loop.tools.definitions.filter { $0.name != outer.name } },
            call: { name, input in
                guard name != outer.name else { return .error("A script cannot call \(name).") }
                let call = ToolInvocation(id: outer.id, name: name, input: input)
                var (output, contexts) = await loop.passing(
                    call,
                    announce: false,
                    answers: answers,
                    events: answers.record
                ) { _ in
                    loop.approving(loop.context.during(call: outer.id).withinScript(), answers)
                }
                // What a hook adds for the model is added to what the script reads: the model reads only what the script says.
                if !contexts.isEmpty { output.content += "\n" + contexts.joined(separator: "\n") }
                return output
            }
        )
    }
}
