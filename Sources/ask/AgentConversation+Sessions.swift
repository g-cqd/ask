internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Synchronization

extension AgentConversation {
    /// Leaves the current session intact on disk. A new file is created only when a prompt needs it.
    func newSession(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard arguments.isEmpty else {
            update(.notice("Usage: /new (no arguments).", isError: true))
            return
        }
        guard maySwitchSession("new", update: update) else { return }
        let hadSession = session.withLock { $0 != nil }
        activateSession(nil, update: update)
        await adoptSandbox(of: nil, update: update)
        let note =
            hadSession
            ? "New session. The previous one is saved." : "New session. It will be saved when you send a prompt."
        update(.notice(note, isError: false))
    }

    /// Makes the sandbox `session` recorded, or none, the layer below the flags, and reads the settings again.
    func adoptSandbox(of session: SessionRecorder?, update: @Sendable (ConversationUpdate) -> Void) async {
        sourceState.withLock { $0 = $0.resuming(session) }
        await refreshSettings(update: update)
    }

    /// Sessions do not own processes: refuse to carry a running job into another conversation silently.
    func maySwitchSession(_ command: String, update: @Sendable (ConversationUpdate) -> Void) -> Bool {
        let running = jobs.running
        guard running.isEmpty else {
            update(
                .notice(
                    "/\(command): Cannot switch sessions while jobs are running (\(running.joined(separator: ", "))). Stop them first.",
                    isError: true))
            return false
        }
        return true
    }

    /// Called only between runs, once a replacement has been opened successfully. Releasing the old recorder
    /// also releases its writer lock. Learned window state must not carry over from another session.
    func activateSession(_ replacement: SessionRecorder?, update: @Sendable (ConversationUpdate) -> Void) {
        session.withLock { $0 = replacement }
        promptInput.withLock { $0 = nil }
        usage.withLock { $0 = UsageTotals() }
        current.withLock { $0.loop = nil }
        update(.clearConversation)
        for item in history() { update(item) }
    }
}
