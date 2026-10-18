public import AskAI

/// Streams model responses. The composition root adapts a provider client to it; tests script it.
public protocol ModelProvider: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error>
}

/// What a run uses besides its tools.
public struct AgentSettings: Sendable, Equatable {
    public var model: String
    public var maximumTokens: Int
    public var systemPrompt: [String]
    /// The most requests one run may make, so a model that never stops calling tools cannot run forever.
    public var maximumTurns: Int

    /// Settings with these values.
    public init(model: String, maximumTokens: Int, systemPrompt: [String], maximumTurns: Int) {
        self.model = model
        self.maximumTokens = maximumTokens
        self.systemPrompt = systemPrompt
        self.maximumTurns = maximumTurns
    }
}

/// What happens during a run, in order, for a screen or a log.
public enum AgentEvent: Sendable, Equatable {
    /// A streamed step of the current response.
    case model(ModelEvent)
    /// The context needed repairs before this turn's request.
    case repaired([RequestContext.Repair])
    /// A response was complete and recorded.
    case responded(AssembledResponse)
    /// A tool started, with the input the model gave it.
    case toolStarted(id: String, name: String, input: JSONObject)
    /// A tool finished and its result was recorded.
    case toolFinished(id: String, name: String, output: ToolOutput)
    /// The run ended because the model stopped calling tools.
    case finished(StopReason?)
}

/// Why a run ended without finishing.
public enum AgentError: Error, Sendable, Equatable {
    /// The provider failed; its description, for the user.
    case provider(String)
    /// The response stream broke the protocol.
    case assembly(ResponseAssemblyError)
    /// A change could not be recorded. Nothing after it ran.
    case session(SessionFileError)
    /// The run was aborted. Results already known are recorded; calls not yet run are left unanswered.
    case cancelled
    case turnLimit(Int)
}

/// The agent loop: request, stream, record, run tools, record their results, repeat.
///
/// Everything the model or a tool produces is recorded as soon as it is complete, so an interrupted run
/// resumes from exactly what happened. A response cut off mid-stream is not recorded as if it were complete.
public struct AgentLoop: Sendable {
    private let provider: any ModelProvider
    private let tools: ToolRegistry
    private let settings: AgentSettings
    private let context: ToolContext

    /// A loop over `provider` and `tools`.
    public init(provider: any ModelProvider, tools: ToolRegistry, settings: AgentSettings, context: ToolContext) {
        self.provider = provider
        self.tools = tools
        self.settings = settings
        self.context = context
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
        var assembler = ResponseAssembler()
        do {
            for try await event in provider.stream(request) {
                try assembler.apply(event)
                events(.model(event))
            }
        } catch let error as ResponseAssemblyError {
            throw .assembly(error)
        } catch {
            throw Task.isCancelled ? .cancelled : .provider(String(describing: error))
        }
        guard !Task.isCancelled else { throw .cancelled }
        do { return try assembler.finish() } catch { throw .assembly(error) }
    }

    private func record(_ payload: SessionPayload, in session: SessionRecorder) throws(AgentError) {
        do { try session.append(payload) } catch { throw .session(error) }
    }
}
