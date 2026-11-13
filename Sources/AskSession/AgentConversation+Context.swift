internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization

extension AgentConversation {
    /// Capacity is read afresh so switching models cannot leave the old denominator on screen.
    func contextUpdate() -> ConversationUpdate {
        let limit = current.withLock { $0.settings.model.contextWindow }
        return .context(usage.withLock { $0.contextStatus(limit: limit) })
    }

    /// Keep spend cumulative, but occupancy belongs to one response, never the sum of requests.
    func recordUsage(_ event: AgentEvent) {
        guard let spent = event.usage else { return }
        let compacted: Bool
        if case .compacted = event { compacted = true } else { compacted = false }
        usage.withLock { $0.add(spent, isCompaction: compacted) }
    }
}
