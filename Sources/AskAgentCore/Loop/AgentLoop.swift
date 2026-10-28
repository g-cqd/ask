internal import AskAI

/// The agent loop: request, stream, record, run tools, record their results, repeat.
///
/// Everything the model or a tool produces is recorded as soon as it is complete, so an interrupted run
/// resumes from exactly what happened. A response cut off mid-stream is not recorded as if it were complete.
public struct AgentLoop: Sendable {
    let provider: any ModelProvider
    let tools: ToolRegistry
    let settings: AgentSettings
    private let context: ToolContext
    let retry: RetryPolicy
    let clock: any Clock<Duration>
    private let hooks: [any AgentHook]
    let learnedWindow = LearnedWindow()

    /// What the loop sends, as a recorded user message, after a response stopped at the output-token limit.
    public static let continuationPrompt =
        "[ask] Your previous response was cut off at the output token limit. Continue from where you stopped. "
        + "If you were writing a tool call, it was dropped: issue it again, in smaller steps if it was large."

    /// What the loop sends, as a recorded user message, after a response stopped because the context window
    /// was full. The conversation is compacted before it is sent.
    public static let contextFullPrompt =
        "[ask] The context window filled up and the conversation was compacted. Continue from where you stopped."

    /// A loop over `provider` and `tools`, retrying transient failures per `retry` and waiting on `clock`.
    public init(
        provider: any ModelProvider, tools: ToolRegistry, settings: AgentSettings, context: ToolContext,
        retry: RetryPolicy = .standard, clock: any Clock<Duration> = ContinuousClock(), hooks: [any AgentHook] = []
    ) {
        self.hooks = hooks
        self.provider = provider
        self.tools = tools
        self.settings = settings
        self.context = context
        self.retry = retry
        self.clock = clock
    }

    /// What a tool output clipped to fit the window says in place of its middle.
    static let clipNote = "omitted to fit the context window; read again with an offset and limit for the rest"

    /// Whether generation stopped because the context window filled, not because the reply reached its limit.
    ///
    /// Anthropic says so in its stop reason. llama.cpp says `length` for both, so a reply stopped for length having
    /// written less than it was allowed is taken as a full window: asking it to continue would only fill it again
    /// (diary 14, six continuations in a row on an 8k server). A provider that reports no output count is trusted.
    static func filledTheWindow(_ response: AssembledResponse, allowedOutput: Int) -> Bool {
        switch response.stopReason {
            case .contextWindowExceeded: true
            case .maxTokens: (response.usage.output ?? allowedOutput) < allowedOutput
            default: false
        }
    }

    /// Runs one call through the hooks and the tool: each hook may rewrite or block it, then each may transform
    /// the result. A blocked call never runs; its result is an error naming the reason.
    private func runTool(_ original: ToolInvocation, events: (AgentEvent) -> Void) async -> ToolOutput {
        var call = original
        for hook in hooks {
            switch await hook.toolCall(call) {
                case .allow: continue
                case .rewrite(let input): call = ToolInvocation(id: call.id, name: call.name, input: input)
                case .block(let reason):
                    events(.toolStarted(id: call.id, name: call.name, input: call.input))
                    return .error("This call was blocked before it ran: \(reason)")
            }
        }
        events(.toolStarted(id: call.id, name: call.name, input: call.input))
        var output = await tools.run(name: call.name, input: call.input, in: context)
        for hook in hooks { output = await hook.toolResult(call, output) }
        return output
    }

    /// Runs `prompt` to completion in `session`, reporting each step to `events`.
    /// Queued steering enters after a response and all its tool results; follow-ups enter only when the run
    /// would finish. One message enters per boundary, with steering first. Unsent input remains queued on failure.
    /// - Parameters:
    ///   - prompt: the initial user message.
    ///   - session: where completed work is persisted.
    ///   - input: messages queued while this run is in flight; nil for a run without interactive input.
    ///   - events: completed steps, including acknowledgments of persisted queued messages.
    /// - Throws: an ``AgentError``. Cancelling the task aborts the run as ``AgentError/cancelled``.
    public func run(
        _ prompt: String, in session: SessionRecorder, input: PromptQueue? = nil, events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        try record(.user(prompt), in: session)
        var watch = WindowWatch()
        for turn in 0 ..< settings.maximumTurns {
            if compactionDue(session, contextFull: watch.contextFull) {
                try await compact(session, contextFull: watch.contextFull, events: events)
            }
            let allowedOutput = budget.maximumTokens
            let response: AssembledResponse
            do {
                response = try await respond(to: session.tree, events: events)
            } catch .contextOverflow(let reason) {
                // Refused for its length: compact and send the shorter conversation, once.
                try watch.overflowed(reason)
                try await compact(session, contextFull: true, events: events)
                continue
            }
            watch.responded()
            try record(.response(response), in: session)
            events(.responded(response))
            let filled = Self.filledTheWindow(response, allowedOutput: allowedOutput)
            // What the reply held when the window filled is the window: size every later request to it.
            if filled { learnedWindow.learn(Self.contextTokens(of: response)) }
            try watch.observe(filled: filled)
            let calls = Self.toolCalls(in: response)
            let continuing: Bool
            if calls.isEmpty {
                continuing = try continuesWithoutCalls(response, filled: filled, in: session, events: events)
            } else {
                try await runTurn(calls, in: session, events: events)
                continuing = true
            }
            guard !Task.isCancelled else { throw .cancelled }
            if try acceptInput(
                input, finished: !continuing, atLimit: turn + 1 == settings.maximumTurns, in: session, events: events)
            {
                continue
            }
            if !continuing {
                events(.finished(response.stopReason))
                return
            }
        }
        throw .turnLimit(settings.maximumTurns)
    }

    /// The tool calls a response makes, in order.
    static func toolCalls(in response: AssembledResponse) -> [ToolInvocation] {
        response.blocks.compactMap { block in
            guard case .toolCall(let id, let name, let input) = block else { return nil }
            return ToolInvocation(id: id, name: name, input: input)
        }
    }

    /// What a reply without tool calls means: the run is done, or it goes on after recording why.
    /// - Returns: whether the run continues.
    private func continuesWithoutCalls(
        _ response: AssembledResponse, filled: Bool, in session: SessionRecorder, events: (AgentEvent) -> Void
    ) throws(AgentError) -> Bool {
        if filled {
            // The window filled: the next request is compacted first; say why the reply stopped.
            try record(.user(Self.contextFullPrompt), in: session)
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
    private func runTurn(_ calls: [ToolInvocation], in session: SessionRecorder, events: (AgentEvent) -> Void)
        async throws(AgentError)
    {
        let limit = budget.toolOutputBytes.map { Swift.max(512, $0 / calls.count) }
        for call in calls {
            guard !Task.isCancelled else { throw .cancelled }
            var output = await runTool(call, events: events)
            if let limit { output.content = Compaction.clipped(output.content, toBytes: limit, note: Self.clipNote) }
            try record(
                .toolResult(callID: call.id, content: output.content, isError: output.isError, images: output.images),
                in: session)
            events(.toolFinished(id: call.id, name: call.name, output: output))
        }
        guard !Task.isCancelled else { throw .cancelled }
    }

    /// Streams one response for the tree's context and assembles it.
    private func respond(to tree: SessionTree, events: (AgentEvent) -> Void) async throws(AgentError)
        -> AssembledResponse
    {
        try await stream(request(for: tree.context(), events: events), events: events)
    }

    /// The request for `context`, reporting any repair it needed.
    func request(for context: [SessionEntry], events: (AgentEvent) -> Void) -> ModelRequest {
        let built = RequestContext(context)
        if !built.repairs.isEmpty { events(.repaired(built.repairs)) }
        return ModelRequest(
            model: settings.model, maxTokens: budget.maximumTokens, systemPrompt: settings.systemPrompt,
            messages: built.messages, tools: tools.definitions, thinking: settings.thinking)
    }

    func record(_ payload: SessionPayload, in session: SessionRecorder) throws(AgentError) {
        do { try session.append(payload) } catch { throw .session(error) }
    }
}
