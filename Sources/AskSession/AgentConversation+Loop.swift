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
            var hooks = loopHooks(current.settings)
            hooks.extraHooks = [goalHook(current.settings)]
            let created = try makeLoop(current.settings, hooks).handing(over: handover)
            current.loop = created
            return created
        }
    }

    /// The loop threads run on (roadmap 0195): main's, or one for `threads.model`, built once and dropped when the settings change.
    /// `model`: a thread's own, from `/model` in its lane (owner, 2026-11-26): its loop is built for it, not kept.
    func threadLoop(model: String? = nil) async throws -> AgentLoop {
        if let model {
            let settings = try await settings(forModel: model)
            mcp.apply(settings.configuration.mcp.value.servers)
            return try makeLoop(settings, loopHooks(settings))
        }
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

    /// The model a thread works with, as the status line names it in its lane: its own, `threads.model`, or the conversation's.
    func threadModelLabel(_ own: String?) async -> String {
        let word = own ?? current.withLock { $0.settings.configuration.threads.value.threadModel }
        guard let word, let settings = try? await settings(forModel: word) else {
            return current.withLock { $0.settings.model.label }
        }
        return settings.model.label
    }

    /// The settings in force with `word` as the model, read as `/model` reads its word; throws when it does not resolve.
    func settings(forModel word: String) async throws -> RunSettings {
        let (provider, model) = serving(word)
        var candidate = source
        candidate.flags.selected = ModelSelection(provider: provider, model: model)
        return try await candidate.load(allowNetwork: false)
    }

    /// What a loop built for `settings` calls back into the conversation for.
    /// `subagents`: whether its model may start subagents; a subagent's loop may not (roadmap 0063: depth 1).
    func loopHooks(_ settings: RunSettings, subagents: Bool = true) -> LoopHooks {
        let subagentStarter: SubagentTask.Starter = { [weak self] task in
            await self?.startSubagent(task) ?? .refused("ask is closing.")
        }
        return LoopHooks(
            approve: { [weak self] in await self?.approve($0) ?? false },
            narrowing: narrowing,
            lists: lists,
            destructiveApprover: { [weak self] in await self?.approveDestructive($0) ?? false },
            callGate: callGate(for: settings),
            askPerson: { [weak self] in await self?.askPerson($0) },
            // A running call's progress goes to the screen of the run it belongs to (roadmap 0067).
            progress: { [weak self] call, line in
                self?.approvals.withLock { $0.ask }?(.toolProgress(id: call, text: line))
            },
            startSubagent: subagents ? subagentStarter : nil,
            reportEvent: { [weak self] event in
                guard let self, let ask = self.approvals.withLock({ $0.ask }) else { return }
                self.deliver(event, to: ask)
            },
            currentSession: { [weak self] in self?.session.withLock { $0 } },
            skillShelf: skillTrust.shelf
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
                    _ = lists.follow(recorder, scope: scope)
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

/// What makes a conversation's loop from its settings and its hooks: the tools over `jobs`, the servers of `mcp`, a transport of
/// its own. The screen's conversation and a served one (ADR-0154) are made with the same. `asksPerson`: whether the model is
/// offered the tool that asks the person questions; a served client that shows no form has nobody to put them to.
func conversationLoop(
    instructions files: [ProjectInstructions.File],
    jobs: JobTable,
    mcp: MCPHub,
    asksPerson: Bool = true
) -> @Sendable (RunSettings, LoopHooks) throws -> AgentLoop {
    { settings, hooks in
        try makeLoop(
            settings,
            instructions: files,
            jobs: jobs,
            transport: URLSessionTransport(),
            // @dl:accept -- the hooks passed through, one argument per field
            approve: hooks.approve,
            narrowing: hooks.narrowing,
            lists: hooks.lists,
            live: mcp.live,
            destructiveApprover: hooks.destructiveApprover,
            callGate: hooks.callGate,
            askPerson: asksPerson ? hooks.askPerson : nil,
            progress: hooks.progress,
            startSubagent: hooks.startSubagent,
            keepTools: hooks.keepTools,
            currentSession: hooks.currentSession,
            extraHooks: hooks.extraHooks,
            reportEvent: hooks.reportEvent,
            skillShelf: hooks.skillShelf
        )
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
    let workingDirectory = source.workspace
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
            makeLoop: conversationLoop(instructions: files, jobs: jobs, mcp: mcp)
        )
        // A shutdown signal exits at once from the screen, so its jobs are signalled there; a normal quit
        // stops them gracefully below.
        // Standard error is the screen's terminal: kept in a file for the screen's life (the owner, 2026-11-14).
        let exit = try await keepingStandardErrorOffTheScreen {
            try await runInteractiveScreen(
                conversation: conversation,
                label: settings.label,
                history: conversation.openingUpdates(settings, reloaded: reloaded, pickSession: pickSession),
                notices: startupNotices + settings.description,
                details: details + settings.detailLines + ProjectInstructions.describe(files),
                options: settings.screenOptions,
                beforeSignalExit: { jobs.terminateAllNow() }
            )
        }
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

extension AgentConversation {
    /// What the screen opens with: the model's label, whether the sandbox is on, the session's history and threads, the thread a
    /// reload left shown (roadmap 0195), and the session picker when it was asked for.
    func openingUpdates(_ settings: RunSettings, reloaded: ReloadNotice?, pickSession: Bool) -> [ConversationUpdate] {
        [.labelVariants(settings.labelVariants), .sandboxActive(!settings.sandbox.isUnrestricted)]
            + history() + restoreThreads()
            + (reloaded?.focusThread.map { [.focusThread(id: $0)] } ?? [])
            + (pickSession ? sessionPickerOpening() : [])
    }
}
