internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Synchronization

/// The configuration files are watched, and a change is applied at once (roadmap 0127): between turns, and during one from its
/// next request (roadmap 0113); never over the draft. An invalid file keeps the last valid settings and says why, once, as the read
/// before each prompt always did (ADR-0031).
extension AgentConversation {
    /// The files whose changes reload the configuration: the user's, the project's, the trust list and the providers.
    var watchedConfigurationFiles: [String] {
        let source = source
        return [source.loader.userPath, source.loader.projectPath, source.loader.trustPath, source.providersPath]
    }

    /// Watches the configuration files and, when ask knows its executable, that too, until cancelled: a configuration
    /// change is applied while idle, and the first new build is announced once. The first new build means "a build
    /// appeared", not "a build is finished": /reload's self-check decides that.
    func watchFiles(since startup: BinaryIdentity?, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let configuration = watchedConfigurationFiles
        var binary = startup.map(BinaryWatcher.init(since:))
        func announceNewBuild() {
            guard binary?.look() != nil else { return }
            update(.detail("A new ask binary appeared. /reload checks it and switches to it."))
            binary = nil
        }
        // A build that landed before the watch began raised no event.
        announceNewBuild()
        for await changed in FileChangeSignal.changes(of: configuration + (binary.map { [$0.path] } ?? [])) {
            if let path = binary?.path, changed.contains(path) { announceNewBuild() }
            if !changed.isDisjoint(with: configuration) { await configurationFilesChanged(update: update) }
        }
    }

    /// A turn starts. Its own start reads the files, so a change waiting for it is already applied.
    func beginTurn() {
        keepAwake.turnStarted()
        current.withLock { $0.turnRunning = true }
    }

    /// A turn ended.
    func endTurn(update: @escaping @Sendable (ConversationUpdate) -> Void) {
        keepAwake.turnEnded()
        current.withLock { $0.turnRunning = false }
    }

    /// A configuration file changed: the files are read now, a running turn takes the change on its next request, and new or
    /// changed MCP servers start now rather than on the next prompt.
    func configurationFilesChanged(update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        await refreshSettings(update: update)
        mcp.apply(current.withLock { $0.settings.configuration.mcp.value.servers })
    }
}
