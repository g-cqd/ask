internal import AskAI

extension AgentLoop {
    /// The request for `context`, reporting any repair it needed.
    func request(for context: [SessionEntry], events: (AgentEvent) -> Void) -> ModelRequest {
        // Old output and reasoning before the kept tail leave the request once the context nears compaction (roadmap 0032).
        let reach = budget.compactAtTokens.flatMap { threshold in
            ContextClearing.reach(
                in: context,
                at: Int(Double(threshold) * ContextClearing.share),
                keepingRecentBytes: budget.keepRecentBytes
            )
        }
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
}
