internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// Runs prompts through the agent loop, recording them in one session.
///
/// The loop and the session are both made on the first prompt, not at launch: nothing needs them before then,
/// and building the loop measured about 1.2 ms of cold start.
///
/// Configuration is read again before every prompt (ADR-0031): a valid change takes effect on that prompt and is reported; an
/// invalid one is reported once and the previous settings stay.
final class AgentConversation: Conversation {
    /// Where settings are read from; `/model` replaces it with one carrying the run's selection.
    let sourceState: Mutex<ConfigurationSource>
    var source: ConfigurationSource { sourceState.withLock { $0 } }
    private let makeLoop:
        @Sendable (RunSettings, SandboxApprover?, SessionNarrowing, DestructiveApprover?) throws -> AgentLoop
    /// The sandbox the model narrowed this conversation to; it outlives loop rebuilds, not /new or /resume.
    let narrowing = SessionNarrowing()
    /// Approval questions waiting for an answer, the grants for this session, and where to ask (roadmap 0019).
    let approvals = Mutex(Approvals())
    let directory: SessionDirectory
    let current: Mutex<Current>
    let session = Mutex<SessionRecorder?>(nil)
    /// Launch consent is consumed once, not reused to authorize an account replacement later in this process.
    private let destinationSelected = Mutex(false)
    let usage = Mutex(UsageTotals())
    let promptInput = Mutex<PromptQueue?>(nil)
    /// Whether the user was told about project skills waiting for trust: once, on the first prompt.
    let skillNoticeGiven = Mutex(false)
    /// Jobs outlive turns, not a reload: `/reload` refuses while any run, or stops them when told to.
    let jobs: JobTable
    /// The MCP servers, which outlive the loop and follow the configuration (ADR-0099).
    let mcp: MCPHub
    /// The questions a command asked the person (a code, a key), waiting for an answer.
    let inputs = InputBroker()
    /// The build that is running, and the one a successful `/reload` chose, which ``reExecute()`` starts.
    let startup = BinaryIdentity.running()
    let reloadTarget = Mutex<BinaryIdentity?>(nil)

    /// The settings in force, the loop built from them, and the last reload error shown.
    struct Current {
        var settings: RunSettings
        var loop: AgentLoop?
        var shownError: String?
    }

    /// - Parameters:
    ///   - directory: where a new session is created on the first prompt.
    ///   - resumed: a session already open, which prompts continue instead.
    ///   - settings: what the run starts with.
    ///   - source: where the settings come from, read again before each prompt, all or nothing.
    ///   - jobs: the jobs `/reload` must not orphan.
    ///   - mcp: the MCP servers, started with the settings and kept across loop rebuilds.
    ///   - makeLoop: builds the loop for some settings, on the first prompt and after a change.
    init(
        directory: SessionDirectory, resumed: SessionRecorder? = nil, settings: RunSettings,
        source: ConfigurationSource, jobs: JobTable, mcp: MCPHub,
        makeLoop:
            @escaping @Sendable (
                RunSettings, SandboxApprover?, SessionNarrowing, DestructiveApprover?
            ) throws -> AgentLoop
    ) {
        sourceState = Mutex(source)
        self.jobs = jobs
        self.mcp = mcp
        self.makeLoop = makeLoop
        self.directory = directory
        current = Mutex(Current(settings: settings))
        session.withLock { $0 = resumed }
    }

    /// Reads the configuration again and, when it changed, tells the screen what changed. The loop is rebuilt
    /// on the next use.
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
        let updates: [ConversationUpdate] = current.withLock { current in
            current.shownError = nil
            let updates = fresh.updates(replacing: current.settings)
            if fresh.differs(from: current.settings) { current.loop = nil }
            current.settings = fresh
            return updates
        }
        for item in updates { update(item) }
        update(contextUpdate())
    }

    /// What the screen shows first for a resumed session: its conversation, then its usage so far, which the
    /// status line keeps adding to.
    func history() -> [ConversationUpdate] {
        guard let tree = session.withLock({ $0?.tree }) else { return [contextUpdate()] }
        var updates: [ConversationUpdate] = []
        for step in SessionReplay.steps(tree.activeBranch()) {
            switch step {
                case .prompt(let text): updates.append(.userPrompt(text))
                case .event(let event):
                    recordUsage(event)
                    if let shown = Self.update(for: event) { updates.append(shown) }
            }
        }
        return updates + [.status(usage.withLock { $0.compact }), contextUpdate()]
    }

    func enqueue(_ text: String, id: Int, followUp: Bool) {
        promptInput.withLock { $0 }?
            .append(
                QueuedPrompt(
                    id: id, text: text, delivery: followUp ? .followUp : .steering))
    }

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        let input = PromptQueue()
        promptInput.withLock { $0 = input }
        // Approval questions during this run go to this run's screen updates.
        approvals.withLock { $0.ask = update }
        return Task {
            do {
                await self.refreshSettings(update: update)
                self.noticeUntrustedSkills(update: update)
                guard let prompt = self.expandingSkill(prompt, update: update) else {
                    update(.runEnded)
                    return
                }
                let loop = try self.agentLoop()
                let recorder = try self.recorder()
                try self.current.withLock { $0.settings }.record(in: recorder)
                try await loop.run(prompt, in: recorder, input: input) { self.deliver($0, to: update) }
            } catch {
                self.report(error, to: update)
                update(.returnQueuedPrompts)
            }
            update(.runEnded)
        }
    }

    /// Shows an event on the screen and adds what it cost to the status line.
    func deliver(_ event: AgentEvent, to update: @Sendable (ConversationUpdate) -> Void) {
        if event.usage != nil {
            recordUsage(event)
            update(.status(usage.withLock { $0.compact }))
            update(contextUpdate())
        }
        if let shown = Self.update(for: event) { update(shown) }
    }

    /// Says why a run or command ended without finishing.
    func report(_ error: any Error, to update: @Sendable (ConversationUpdate) -> Void) {
        if case AgentError.cancelled = error {
            update(.notice("Aborted. Results already known were kept.", isError: false))
        } else {
            update(.notice("ask: \(error)", isError: true))
        }
    }

    func agentLoop() throws -> AgentLoop {
        try current.withLock { current throws -> AgentLoop in
            if let existing = current.loop { return existing }
            mcp.apply(current.settings.configuration.mcp.value.servers)
            let created = try makeLoop(
                current.settings, { [weak self] in await self?.approve($0) ?? false }, narrowing,
                { [weak self] in await self?.approveDestructive($0) ?? false })
            current.loop = created
            return created
        }
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
                    try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
                    recorder = SessionRecorder(try SessionFile.create(at: FilePath(directory.newSessionPath())))
                }
                try recorder.select(
                    destination,
                    explicitlySelected: source.flags.selected != nil || (!selected && source.flags.provider != nil))
                selected = true
                existing = recorder
                return recorder
            }
        }
    }
}

/// The interactive screen in the working directory.
func runInteractive(
    source: ConfigurationSource, settings: RunSettings, resumed: SessionRecorder?, startupNotices: [String],
    reloaded: ReloadNotice?
) async {
    let workingDirectory = FileManager.default.currentDirectoryPath
    let directory = SessionDirectory(project: workingDirectory, environment: LaunchEnvironment.values)
    let details = startupDetails(resumed: resumed, reloaded: reloaded)
    let jobs = JobTable(environment: LaunchEnvironment.values)
    // Started now, not on the first prompt, so the servers are connecting while the person types.
    let mcp = startMCPServers(settings, jobs: jobs)
    do {
        let files = instructionFiles(workingDirectory: workingDirectory)
        let conversation = AgentConversation(
            directory: directory, resumed: resumed, settings: settings, source: source, jobs: jobs, mcp: mcp,
            makeLoop: { settings, approve, narrowing, destructiveApprover in
                try makeLoop(
                    settings, instructions: files, jobs: jobs,
                    transport: URLSessionTransport(), approve: approve, narrowing: narrowing, live: mcp.live,
                    destructiveApprover: destructiveApprover)
            })
        // A shutdown signal exits at once from the screen, so its jobs are signalled there; a normal quit
        // stops them gracefully below.
        let exit = try await runInteractiveScreen(
            conversation: conversation, label: settings.label,
            history: [.labelVariants(settings.labelVariants)] + conversation.history(),
            notices: startupNotices + settings.description,
            details: details + settings.detailLines + ProjectInstructions.describe(files),
            options: settings.screenOptions, beforeSignalExit: { jobs.terminateAllNow() })
        await jobs.stopAll()
        await mcp.stop()
        // The terminal is already restored: replace this process with the new build, resuming this session.
        if exit == .reload { conversation.reExecute() }
    } catch {
        await jobs.stopAll()
        await mcp.stop()
        // The screen has already restored the terminal by the time an error reaches here.
        fail("ask: \(error)", code: 70)
    }
}
