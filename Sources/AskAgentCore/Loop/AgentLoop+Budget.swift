internal import AskAI

extension AgentLoop {
    /// How many times in a row the window may fill and be compacted before the run stops: a compaction that cannot
    /// make room would otherwise repeat until the turn limit (diary 14).
    public static let fullWindowCompactionsBeforeGivingUp = 3

    /// The reply limit, compaction threshold and kept tail for the next request: the configured ones, narrowed to
    /// fit a window the server showed it has (``ContextBudget``'s rules). Never wider than configured.
    var budget: ContextBudget {
        let configured = ContextBudget(
            maximumTokens: settings.maximumTokens, compactAtTokens: settings.compactAtTokens,
            keepRecentBytes: settings.keepRecentBytes, toolOutputBytes: settings.toolOutputBytes)
        guard let window = learnedWindow.window else { return configured }
        let fitted = ContextBudget(
            contextWindow: window, maxOutputTokens: settings.maximumTokens, requestedCompactAt: settings.compactAtTokens
        )
        return ContextBudget(
            maximumTokens: Swift.min(configured.maximumTokens, fitted.maximumTokens),
            compactAtTokens: fitted.compactAtTokens,
            keepRecentBytes: Swift.min(configured.keepRecentBytes, fitted.keepRecentBytes),
            toolOutputBytes: [configured.toolOutputBytes, fitted.toolOutputBytes].compactMap(\.self).min())
    }

    /// The tokens a response's context held: its prompt, read from cache or not, plus its reply.
    static func contextTokens(of response: AssembledResponse) -> Int {
        let usage = response.usage
        return (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheCreation ?? 0) + (usage.output ?? 0)
    }
}
