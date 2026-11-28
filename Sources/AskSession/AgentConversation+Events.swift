internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Synchronization

extension AgentConversation {
    /// Reads the workspace's git state again for the status bar.
    func refreshGitStatus(_ update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let workspace = current.withLock { $0.settings.workspace }
        let path = LaunchEnvironment.values["PATH"]
        gitStatus.request { update(.gitStatus(await GitStatus.read(in: workspace, path: path))) }
    }

    /// Reads the workspace's open pull requests and issues, and its branch's pull request, when they are due.
    func refreshForge(_ update: @escaping @Sendable (ConversationUpdate) -> Void) {
        forge.request(in: current.withLock { $0.settings.workspace }, update: update)
    }

    /// Shows an event on the screen and adds what it cost to the status line.
    func deliver(_ event: AgentEvent, to update: @escaping @Sendable (ConversationUpdate) -> Void) {
        if event.usage != nil {
            recordUsage(event)
            update(.status(usage.withLock { $0.compact }))
            update(contextUpdate())
        }
        for shown in Self.updates(for: event) { update(shown) }
        // A tool may have changed the files or the branch.
        if case .toolFinished = event { refreshGitStatus(update) }
        if case .toolFinished(_, "tasks", _) = event { sayTaskSpend(update: update) }
        if case .compacted(let summary, _) = event {
            renameConversation(fromSummary: summary, update: update)
            sayCompactionSpend(update: update)
            // What a compaction folds away stays searchable: the index takes it now (t209).
            // From a snapshot: the task must not hold the session, which the person may leave meanwhile (roadmap 0230).
            if let recorder = session.withLock({ $0 }) {
                let (path, snapshot) = (recorder.path, SessionSearch.Snapshot(of: recorder))
                Task.detached(priority: .utility) { await SessionSearch.of(session: path).update(from: snapshot) }
            }
        }
    }
}
