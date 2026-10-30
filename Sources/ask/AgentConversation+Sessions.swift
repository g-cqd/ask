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
        await adoptRecords(of: nil, update: update)
        let note =
            hadSession
            ? "New session. The previous one is saved." : "New session. It will be saved when you send a prompt."
        update(.notice(note, isError: false))
    }

    /// Adopts what `session` recorded, or nothing for a new one: its destination is pinned and its strict sandbox
    /// becomes the layer below the flags. Resuming also drops this run's `/model` choice, so a session goes back where
    /// it was sent rather than silently moving to another model; a new session keeps the choice. Then the settings
    /// are read again.
    func adoptRecords(of session: SessionRecorder?, update: @Sendable (ConversationUpdate) -> Void) async {
        sourceState.withLock { source in
            source = source.resuming(session)
            if session != nil { source.flags.selected = nil }
        }
        await refreshSettings(update: update)
    }

    /// The open session if it has recorded anything; otherwise says `message` and returns nil.
    func recordedSession(orSay message: String, update: @Sendable (ConversationUpdate) -> Void) -> SessionRecorder? {
        guard let recorder = session.withLock({ $0 }), !recorder.tree.entries.isEmpty else {
            update(.notice(message, isError: false))
            return nil
        }
        return recorder
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
        // The model's narrowing belongs to the conversation it was made in.
        narrowing.policy = nil
        promptInput.withLock { $0 = nil }
        usage.withLock { $0 = UsageTotals() }
        current.withLock { $0.loop = nil }
        // One update, drawn once, as `/rewind` sends it (roadmap 0160).
        update(.batch([.clearConversation] + history()))
    }
}
