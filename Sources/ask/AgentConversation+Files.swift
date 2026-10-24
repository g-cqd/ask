internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Synchronization

/// The files the `@` picker offers (roadmap 0048, ADR-0069).
extension AgentConversation {
    /// The project's files under the sandbox in force now: what the working directory holds that ask may read.
    func projectFiles() async -> ProjectFiles {
        let settings = current.withLock { $0.settings }
        let listing = await ProjectLister.list(in: settings.workspace, policy: settings.sandbox)
        return ProjectFiles(paths: listing.paths, hidden: listing.hidden, truncated: listing.truncated)
    }
}
