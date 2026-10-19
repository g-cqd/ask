internal import AskAI

/// The agent loop: request, stream, record, run tools, record their results, repeat.
///
/// Everything the model or a tool produces is recorded as soon as it is complete, so an interrupted run
/// resumes from exactly what happened. A response cut off mid-stream is not recorded as if it were complete.
public struct AgentLoop: Sendable {
    private let provider: any ModelProvider
    private let tools: ToolRegistry
    private let settings: AgentSettings
    private let context: ToolContext
    private let retry: RetryPolicy
    private let clock: any Clock<Duration>

    /// A loop over `provider` and `tools`, retrying transient failures per `retry` and waiting on `clock`.
    public init(
        provider: any ModelProvider, tools: ToolRegistry, settings: AgentSettings, context: ToolContext,
        retry: RetryPolicy = .standard, clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.provider = provider
        self.tools = tools
        self.settings = settings
        self.context = context
        self.retry = retry
        self.clock = clock
    }

    /// Runs `prompt` to completion in `session`, reporting each step to `events`.
    /// - Throws: an ``AgentError``. Cancelling the task aborts the run as ``AgentError/cancelled``.
    public func run(
        _ prompt: String, in session: SessionRecorder, events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        try record(.user(prompt), in: session)
        for _ in 0 ..< settings.maximumTurns {
            let response = try await respond(to: session.tree, events: events)
            try record(.response(response), in: session)
            events(.responded(response))
            let calls = response.blocks.compactMap { block -> (String, String, JSONObject)? in
                guard case .toolCall(let id, let name, let input) = block else { return nil }
                return (id, name, input)
            }
            if calls.isEmpty, response.stopReason != .pauseTurn {
                events(.finished(response.stopReason))
                return
            }
            for (id, name, input) in calls {
                guard !Task.isCancelled else { throw .cancelled }
                events(.toolStarted(id: id, name: name, input: input))
                let output = await tools.run(name: name, input: input, in: context)
                try record(.toolResult(callID: id, content: output.content, isError: output.isError), in: session)
                events(.toolFinished(id: id, name: name, output: output))
            }
            guard !Task.isCancelled else { throw .cancelled }
        }
        throw .turnLimit(settings.maximumTurns)
    }

    /// Streams one response for the tree's context and assembles it.
    private func respond(to tree: SessionTree, events: (AgentEvent) -> Void) async throws(AgentError)
        -> AssembledResponse
    {
        let built = RequestContext(tree.context())
        if !built.repairs.isEmpty { events(.repaired(built.repairs)) }
        let request = ModelRequest(
            model: settings.model, maxTokens: settings.maximumTokens, systemPrompt: settings.systemPrompt,
            messages: built.messages, tools: tools.definitions)
        var attempt = 1
        while true {
            var assembler = ResponseAssembler()
            var shown = false
            do {
                for try await event in provider.stream(request) {
                    try assembler.apply(event)
                    shown = true
                    events(.model(event))
                }
            } catch let error as ResponseAssemblyError {
                throw .assembly(error)
            } catch {
                if Task.isCancelled { throw .cancelled }
                // Retried only when nothing of this attempt reached the screen: a second attempt would
                // otherwise repeat what was already shown.
                guard !shown, attempt < retry.maximumAttempts, let advice = error as? any RetryAdvice,
                    advice.isRetryable
                else { throw .provider(String(describing: error)) }
                let delay = retry.delay(after: attempt, requested: advice.retryAfter)
                events(
                    .retrying(
                        attempt: attempt + 1, of: retry.maximumAttempts, delay: delay, reason: String(describing: error)
                    ))
                do { try await clock.sleep(for: delay) } catch { throw .cancelled }
                attempt += 1
                continue
            }
            guard !Task.isCancelled else { throw .cancelled }
            do { return try assembler.finish() } catch { throw .assembly(error) }
        }
    }

    private func record(_ payload: SessionPayload, in session: SessionRecorder) throws(AgentError) {
        do { try session.append(payload) } catch { throw .session(error) }
    }
}
