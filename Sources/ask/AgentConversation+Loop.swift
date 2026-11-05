internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

// The agent loop and the session recorder each run is given; apart from AgentConversation.swift to keep
// each file under the 250-line ceiling.
extension AgentConversation {
    func agentLoop() throws -> AgentLoop {
        try current.withLock { current throws -> AgentLoop in
            if let existing = current.loop { return existing }
            mcp.apply(current.settings.configuration.mcp.value.servers)
            let created = try makeLoop(current.settings, loopHooks(current.settings)).handing(over: handover)
            current.loop = created
            return created
        }
    }

    /// The loop threads run on (roadmap 0195): main's, or one for `threads.model`, built once and dropped when the settings change.
    func threadLoop() async throws -> AgentLoop {
        let (word, cached) = current.withLock { ($0.settings.configuration.threads.value.threadModel, $0.threadLoop) }
        guard let word else { return try agentLoop() }
        if let cached { return cached }
        let settings = try await settings(forModel: word)
        mcp.apply(settings.configuration.mcp.value.servers)
        let created = try makeLoop(settings, loopHooks(settings))
        return current.withLock { current in
            if current.threadLoop == nil { current.threadLoop = created }
            return current.threadLoop ?? created
        }
    }

    /// The settings in force with `word` as the model, read as `/model` reads its word; throws when it does not resolve.
    func settings(forModel word: String) async throws -> RunSettings {
        let (provider, model) = serving(word)
        var candidate = source
        candidate.flags.selected = ModelSelection(provider: provider, model: model)
        return try await candidate.load(allowNetwork: false)
    }

    /// What a loop built for `settings` calls back into the conversation for.
    private func loopHooks(_ settings: RunSettings) -> LoopHooks {
        LoopHooks(
            approve: { [weak self] in await self?.approve($0) ?? false },
            narrowing: narrowing,
            destructiveApprover: { [weak self] in await self?.approveDestructive($0) ?? false },
            callGate: callGate(for: settings),
            askPerson: { [weak self] in await self?.askPerson($0) },
            // A running call's progress goes to the screen of the run it belongs to (roadmap 0067).
            progress: { [weak self] call, line in
                self?.approvals.withLock { $0.ask }?(.toolProgress(id: call, text: line))
            },
            reportEvent: { [weak self] event in
                guard let self, let ask = self.approvals.withLock({ $0.ask }) else { return }
                self.deliver(event, to: ask)
            }
        )
    }

    /// The session, created on the first prompt so that opening and closing ask leaves no empty sessions.
    func recorder() throws -> SessionRecorder {
        let destination = current.withLock { SessionRouting.destination($0.settings.model) }
        return try destinationSelected.withLock { selected in
            try session.withLock { existing throws -> SessionRecorder in
                let recorder: SessionRecorder
                if let existing {
                    recorder = existing
                } else {
                    try directory.create()
                    let protection = SessionKeyAccess.protection
                    recorder = SessionRecorder(
                        try SessionFile.create(
                            at: FilePath(takePlannedSession()),
                            format: protection.format,
                            keyring: protection.keyring
                        )
                    )
                    let scope = current.withLock { $0.settings.configuration.taskScope.value }
                    _ = SessionTasks.follow(recorder, scope: scope)
                }
                try recorder.select(
                    destination,
                    explicitlySelected: source.flags.selected != nil || (!selected && source.flags.provider != nil)
                )
                selected = true
                existing = recorder
                return recorder
            }
        }
    }
}

/// The interactive screen in the working directory.
func runInteractive(
    source: ConfigurationSource,
    settings: RunSettings,
    resumed: SessionRecorder?,
    startupNotices: [String],
    reloaded: ReloadNotice?,
    pickSession: Bool = false
) async {
    // Before a new build can replace this one's file, which /reload compares against (roadmap 0153).
    LaunchSignature.start()
    let workingDirectory = FileManager.default.currentDirectoryPath
    let directory = SessionDirectory(project: workingDirectory, environment: LaunchEnvironment.values)
    let details = startupDetails(resumed: resumed, reloaded: reloaded)
    let jobs = JobTable(environment: LaunchEnvironment.values)
    // Connected on the first message, not now (roadmap 0143): an idle ask holds no server's memory.
    let mcp = startMCPServers(settings, jobs: jobs, connectsOnFirstNeed: true)
    do {
        let files = instructionFiles(workingDirectory: workingDirectory)
        let conversation = AgentConversation(
            directory: directory,
            resumed: resumed,
            settings: settings,
            source: source,
            jobs: jobs,
            mcp: mcp,
            grants: reloaded?.grantsPath.flatMap(SessionGrants.take(from:)),
            makeLoop: { settings, hooks in
                try makeLoop(
                    settings,
                    instructions: files,
                    jobs: jobs,
                    transport: URLSessionTransport(),
                    approve: hooks.approve,
                    narrowing: hooks.narrowing,
                    live: mcp.live,
                    destructiveApprover: hooks.destructiveApprover,
                    callGate: hooks.callGate,
                    askPerson: hooks.askPerson,
                    progress: hooks.progress,
                    reportEvent: hooks.reportEvent
                )
            }
        )
        // A shutdown signal exits at once from the screen, so its jobs are signalled there; a normal quit
        // stops them gracefully below.
        let sessionPicker = pickSession ? conversation.sessionPickerOpening() : []
        let exit = try await runInteractiveScreen(
            conversation: conversation,
            label: settings.label,
            history: [.labelVariants(settings.labelVariants), .sandboxActive(!settings.sandbox.isUnrestricted)]
                + conversation.history() + conversation.restoreThreads()
                // The thread a reload left shown is shown again (roadmap 0195).
                + (reloaded?.focusThread.map { [.focusThread(id: $0)] } ?? []) + sessionPicker,
            notices: startupNotices + settings.description,
            details: details + settings.detailLines + ProjectInstructions.describe(files),
            options: settings.screenOptions,
            beforeSignalExit: { jobs.terminateAllNow() }
        )
        await conversation.stopThreads()
        await jobs.stopAll()
        await mcp.stop()
        if exit == .quit { conversation.printResumeCommand() }
        // The terminal is already restored: replace this process with the new build, resuming this session.
        if exit == .reload { conversation.reExecute() }
    } catch {
        await jobs.stopAll()
        await mcp.stop()
        // The screen has already restored the terminal by the time an error reaches here.
        fail("ask: \(error)", code: 70)
    }
}
