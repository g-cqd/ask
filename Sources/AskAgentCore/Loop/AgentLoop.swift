internal import AskAI

/// The agent loop: request, stream, record, run tools, record their results, repeat.
///
/// Everything the model or a tool produces is recorded as soon as it is complete, so an interrupted run
/// resumes from exactly what happened. A response cut off mid-stream is not recorded as if it were complete.
public struct AgentLoop: Sendable {
    // The model, tools and settings are `var` so that a running turn can take a newer loop's (``LoopHandover``, roadmap 0113).
    var provider: any ModelProvider
    var tools: ToolRegistry
    var settings: AgentSettings
    var context: ToolContext
    var retry: RetryPolicy
    let clock: any Clock<Duration>
    /// Where a change made during a turn is offered to it; nil for a loop that keeps its settings.
    var handover: LoopHandover?
    /// The system's route to the network, checked when a request fails (roadmap 0141); nil never waits.
    let network: (any NetworkPath)?
    /// The longest a request waits for the network to come back.
    let networkWait: Duration
    var hooks: [any AgentHook]
    var learnedWindow = LearnedWindow()
    /// How many times hooks continued this run (roadmap 0192).
    var hookContinues = 0
    /// Whether this run said that hooks rewrote its requests (roadmap 0192): once a run.
    var saidRewrite = false
    /// How many session entries there were at the run's start or its last stop, so a stop can tell what came after (roadmap 0192).
    var stopMark = 0
    /// Answers in a row that lost their connection part way (roadmap 0141).
    let drops = DropCount()
    /// Repairs already reported, so an old session's damage is said once and not before every request.
    let reportedRepairs = ReportedRepairs()

    /// What the loop sends, as a recorded user message, after a response stopped at the output-token limit.
    public static let continuationPrompt =
        "[ask] Your previous response was cut off at the output token limit. Continue from where you stopped. "
        + "If you were writing a tool call, it was dropped: issue it again, in smaller steps if it was large."

    /// What the loop sends, as a recorded user message, after the connection dropped part way through a response (roadmap 0141); the
    /// part that arrived is recorded before it.
    public static let reconnectionPrompt =
        "[ask] The connection dropped while you were answering; what arrived is above. Continue exactly where it stopped, without "
        + "repeating it. If you were writing a tool call, it was dropped: issue it again."

    /// The stop reason of a response cut by a dropped connection, as the session keeps it.
    static let droppedStopReason = StopReason.other("ask_connection_lost")

    /// What the loop sends, as a recorded user message, after a response stopped because the context window
    /// was full. The conversation is compacted before it is sent.
    public static let contextFullPrompt =
        "[ask] The context window filled up and the conversation was compacted. Continue from where you stopped."

    /// A loop over `provider` and `tools`, retrying transient failures per `retry` and waiting on `clock`.
    public init(
        provider: any ModelProvider,
        tools: ToolRegistry,
        settings: AgentSettings,
        context: ToolContext,
        retry: RetryPolicy = .standard,
        clock: any Clock<Duration> = ContinuousClock(),
        hooks: [any AgentHook] = [],
        network: (any NetworkPath)? = nil,
        networkWait: Duration = .seconds(300),
        handover: LoopHandover? = nil
    ) {
        self.handover = handover
        self.network = network
        self.networkWait = networkWait
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
    /// the result and add context. A blocked call never runs; its result is an error naming the reason.
    func runTool(_ original: ToolInvocation, events: (AgentEvent) -> Void) async -> (
        output: ToolOutput, contexts: [String]
    ) {
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
                    events(.toolStarted(id: call.id, name: call.name, input: call.input))
                    return (.error("This call was blocked before it ran: \(reason)"), [])
            }
        }
        events(.toolStarted(id: call.id, name: call.name, input: call.input))
        let answers = HookAnswers()
        var output = await tools.run(
            name: call.name,
            input: call.input,
            in: approving(context.during(call: call.id), answers)
        )
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
        _ prompt: String,
        in session: SessionRecorder,
        input: PromptQueue? = nil,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        var loop = self
        loop.stopMark = session.tree.entries.count
        try await loop.drive(prompt, in: session, input: input, events: events)
    }

    /// `run`'s body, on a copy that takes what is offered to it before each request.
    private mutating func drive(
        _ prompt: String,
        in session: SessionRecorder,
        input: PromptQueue?,
        events: (AgentEvent) -> Void
    ) async throws(AgentError) {
        try await recordFirst(prompt, in: session, events: events)
        var watch = WindowWatch()
        var turn = 0
        while turn < settings.maximumTurns {
            takeOffered()
            if compactionDue(session, contextFull: watch.contextFull) {
                try await compact(session, contextFull: watch.contextFull, events: events)
            }
            let allowedOutput = budget.maximumTokens
            let answered: (response: AssembledResponse, rewrite: RequestRewrite?)
            do {
                // nil: a change was offered while a retry waited; the request goes again, to the new loop, without counting.
                guard let reply = try await respond(to: session.tree, events: events) else { continue }
                answered = reply
            } catch .contextOverflow(let reason) {
                // Refused for its length: compact and send the shorter conversation, once.
                try watch.overflowed(reason)
                try await compact(session, contextFull: true, events: events)
                turn += 1
                continue
            }
            watch.responded()
            let response = answered.response
            try await recordResponse(response, rewrite: answered.rewrite, in: session, events: events)
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
            if try await acceptInput(
                input,
                finished: !continuing,
                atLimit: turn + 1 == settings.maximumTurns,
                in: session,
                events: events
            ) {
                turn += 1
                continue
            }
            if !continuing {
                if try await continuesByHook(
                    response,
                    atLimit: turn + 1 == settings.maximumTurns,
                    in: session,
                    events: events
                ) {
                    turn += 1
                    continue
                }
                events(.finished(response.stopReason))
                return
            }
            turn += 1
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
}
