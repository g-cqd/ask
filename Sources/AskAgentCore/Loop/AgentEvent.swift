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
    /// The response stopped at the output-token limit; a continuation request was recorded and sent.
    case continuedAtOutputLimit
    /// The connection dropped after part of the response was shown (roadmap 0141): what arrived was kept, and the model was asked to
    /// carry on from where it stopped.
    case continuedAfterDrop
    /// A request failed with the network gone; the loop waits for it to come back before sending it again (roadmap 0141).
    case waitingForNetwork
    /// A summary of the conversation is being made, to compact it (roadmap 0099); `compacted` or `compactionFailed` follows.
    case compacting
    /// The conversation before the kept tail was replaced by `summary` in context; the session keeps it all.
    /// `usage` is the summarisation request's.
    case compacted(summary: String, usage: TokenUsage)
    /// Compaction was due but no summary could be made; the run continues on the whole context.
    case compactionFailed(String)
    /// A queued user message has been persisted and will enter the next request.
    case promptAccepted(QueuedPrompt)
    /// The run ended because the model stopped calling tools.
    case finished(StopReason?)
}

extension AgentEvent {
    /// The tokens a request cost, on the events that end one: a response, and a compaction's summary.
    public var usage: TokenUsage? {
        switch self {
            case .responded(let response): response.usage
            case .compacted(_, let usage): usage
            default: nil
        }
    }
}
