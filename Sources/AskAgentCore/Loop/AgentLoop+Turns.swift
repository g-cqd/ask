internal import AskAI

// A turn's tool calls, the reply that ends without any, and the records they leave; apart from AgentLoop.swift
// to keep each file under the 250-line ceiling and the type body under 200 lines.
extension AgentLoop {
    /// What a reply without tool calls means: the run is done, or it goes on after recording why.
    /// - Returns: whether the run continues.
    func continuesWithoutCalls(
        _ response: AssembledResponse,
        filled: Bool,
        in session: SessionRecorder,
        events: (AgentEvent) -> Void
    ) throws(AgentError) -> Bool {
        if filled {
            // The window filled: the next request is compacted first; say why the reply stopped.
            try record(.user(Self.contextFullPrompt), in: session)
            return true
        }
        if response.stopReason == Self.droppedStopReason {
            try record(.user(Self.reconnectionPrompt), in: session)
            events(.continuedAfterDrop)
            return true
        }
        switch response.stopReason {
            case .maxTokens:
                // Cut off mid-thought or mid-call: say so in the session and ask the model to carry on.
                try record(.user(Self.continuationPrompt), in: session)
                events(.continuedAtOutputLimit)
                return true
            case .pauseTurn:
                return true
            default:
                return false
        }
    }

    /// Runs a turn's calls in order, recording each result as it arrives. The results cannot be split by
    /// compaction, so with a window known they share what it allows, each keeping its head and tail.
    func runTurn(_ calls: [ToolInvocation], in session: SessionRecorder, events: (AgentEvent) -> Void)
        async throws(AgentError)
    {
        let limit = budget.toolOutputBytes.map { Swift.max(512, $0 / calls.count) }
        var addedContexts: [String] = []
        for (index, call) in calls.enumerated() {
            guard !Task.isCancelled else {
                try recordNotRun(calls[index...], in: session)
                throw .cancelled
            }
            let (rawOutput, contexts) = await runTool(call, events: events)
            addedContexts += contexts
            var output = rawOutput
            if let limit { output.content = Compaction.clipped(output.content, toBytes: limit, note: Self.clipNote) }
            try record(
                .toolResult(
                    callID: call.id,
                    content: output.content,
                    isError: output.isError,
                    images: output.images,
                    facts: output.facts
                ),
                in: session
            )
            events(.toolFinished(id: call.id, name: call.name, output: output))
        }
        if !addedContexts.isEmpty {
            let joined = addedContexts.joined(separator: "\n\n")
            try record(.user(joined), in: session)
            events(.hookAddedContext(joined))
        }
        guard !Task.isCancelled else { throw .cancelled }
    }

    /// Streams one response for the tree's context and assembles it.
    func respond(to tree: SessionTree, events: (AgentEvent) -> Void) async throws(AgentError)
        -> AssembledResponse?
    {
        var req = request(for: tree.context(), events: events)
        var rewrittenBy: [String] = []
        for hook in hooks {
            let current = req
            let decision = await HookDeadline.ask(
                hook,
                at: "request.before",
                clock: clock,
                orElse: .allow,
                timedOut: events
            ) {
                await hook.requestBefore(current)
            }
            if case .rewrite(let next) = decision {
                req = next
                rewrittenBy.append(hook.name)
            }
        }
        if !rewrittenBy.isEmpty { events(.hookRewroteRequest(hooks: rewrittenBy)) }
        return try await stream(req, events: events, handsOver: true)
    }

    /// Records `response`, says so, then shows it to the `response.after` hooks.
    func recordResponse(_ response: AssembledResponse, in session: SessionRecorder, events: (AgentEvent) -> Void)
        async throws(AgentError)
    {
        try record(.response(response), in: session)
        events(.responded(response))
        await notifyResponseAfter(response, events: events)
    }

    /// Calls `responseAfter` hooks once `response` has been recorded.
    private func notifyResponseAfter(_ response: AssembledResponse, events: (AgentEvent) -> Void) async {
        for hook in hooks {
            await HookDeadline.ask(hook, at: "response.after", clock: clock, orElse: (), timedOut: events) {
                await hook.responseAfter(response)
            }
        }
    }

    func record(_ payload: SessionPayload, in session: SessionRecorder) throws(AgentError) {
        do { try session.append(payload) } catch { throw .session(error) }
    }
}
