internal import AskAI

extension AgentLoop {
    /// The request for `context`, reporting any repair it needed.
    func request(for context: [SessionEntry], events: (AgentEvent) -> Void) -> ModelRequest {
        let built = RequestContext(context)
        let fresh = reportedRepairs.unreported(built.repairs)
        if !fresh.isEmpty { events(.repaired(fresh)) }
        return ModelRequest(
            model: settings.model, maxTokens: budget.maximumTokens, systemPrompt: settings.systemPrompt,
            messages: ImagePart.filtering(
                built.messages, accepts: settings.acceptsImages, limits: settings.imageLimits),
            tools: tools.definitions,
            thinking: settings.thinking)
    }
}
