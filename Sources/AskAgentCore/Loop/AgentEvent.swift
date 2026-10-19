public import AskAI

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
    /// A request failed transiently before anything of it was shown; it is sent again after `delay`.
    case retrying(attempt: Int, of: Int, delay: Duration, reason: String)
    /// The run ended because the model stopped calling tools.
    case finished(StopReason?)
}
