internal import AskAI

extension AgentLoop {
    /// The request for `context`, reporting any repair it needed.
    func request(for context: [SessionEntry], events: (AgentEvent) -> Void) -> ModelRequest {
        request(for: context, clearingBefore: clearingReach(in: context), events: events)
    }

    /// How far old output and reasoning leave the request for `context` once it nears compaction (roadmap 0032), or nil.
    func clearingReach(in context: [SessionEntry]) -> Int? {
        budget.compactAtTokens.flatMap { threshold in
            ContextClearing.reach(
                in: context,
                at: Int(Double(threshold) * ContextClearing.share),
                keepingRecentBytes: budget.keepRecentBytes
            )
        }
    }

    /// The request for `context` with the entries before `reach` cleared, reporting any repair it needed.
    func request(for context: [SessionEntry], clearingBefore reach: Int?, events: (AgentEvent) -> Void) -> ModelRequest
    {
        let built = RequestContext(context, clearingBefore: reach)
        let fresh = reportedRepairs.unreported(built.repairs)
        if !fresh.isEmpty { events(.repaired(fresh)) }
        return ModelRequest(
            model: settings.model,
            maxTokens: budget.maximumTokens,
            systemPrompt: settings.systemPrompt,
            messages: ImagePart.filtering(
                built.messages,
                accepts: settings.acceptsImages,
                limits: settings.imageLimits
            ),
            tools: tools.definitions,
            thinking: settings.thinking
        )
    }

    /// The model's window in tokens: the one its provider or the configuration declares, or a smaller one a server showed.
    var knownWindow: Int? { [settings.contextWindow, learnedWindow.window].compactMap(\.self).min() }

    /// The fewest bytes of text a token is taken to hold when deciding that a request cannot fit. Text runs at three to five (the
    /// session of ADR-0155: 4.33), so a request refused here is at least a fifth longer than the window, and usually half.
    static let bytesPerTokenAtMost = 6

    /// Refuses `request` when its text alone is clearly longer than the window, as the server would, without sending it: megabytes
    /// uploaded to be refused, and a refusal some servers word as something else. Nothing is refused while no window is known.
    /// - Throws: ``AgentError/contextOverflow(_:)``.
    func refuseIfClearlyTooLong(_ request: ModelRequest) throws(AgentError) {
        guard let window = knownWindow else { return }
        let bytes = RequestRewrite.textBytes(of: request)
        guard bytes / Self.bytesPerTokenAtMost > window else { return }
        throw .contextOverflow("\(bytes) bytes of text cannot fit a context window of \(window) tokens")
    }
}
