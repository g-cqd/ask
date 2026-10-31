internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The settings in force, read again when they may have changed.
extension AgentConversation {
    /// Reads the configuration again and, when it changed, tells the screen what changed. The loop is rebuilt on the next use, and
    /// a turn running takes it on its next request (roadmap 0113).
    func refreshSettings(update: @Sendable (ConversationUpdate) -> Void) async {
        let fresh: RunSettings
        do {
            fresh = try await source.load()
        } catch {
            let text = "Configuration not reloaded: \(error). Keeping the previous settings."
            let isNew: Bool = current.withLock { current in
                defer { current.shownError = text }
                return current.shownError != text
            }
            if isNew { update(.notice(text, isError: true)) }
            return
        }
        let (updates, handOver): ([ConversationUpdate], Bool) = current.withLock { current in
            current.shownError = nil
            let updates = fresh.updates(replacing: current.settings)
            let changed = fresh.differs(from: current.settings)
            if changed { current.loop = nil }
            current.settings = fresh
            return (updates, changed && current.turnRunning)
        }
        keepAwake.use(fresh.configuration.keepAwake.value, display: fresh.configuration.keepDisplayAwake.value)
        for item in updates { update(item) }
        // A turn running takes the change on its next request (roadmap 0113).
        if handOver {
            do { handover.offer(try agentLoop()) } catch { report(error, to: update) }
        }
        update(contextUpdate())
    }
}
