internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// Runs prompts through the agent loop, recording them in one session.
///
/// The loop and the session are made on the first prompt, not at launch (building the loop measured about 1.2 ms of cold start).
///
/// Configuration is read again before every prompt (ADR-0031): a valid change applies and is reported, an invalid one is reported once.
final class AgentConversation: Conversation {
    /// Where settings are read from; `/model` replaces it with one carrying the run's selection.
    let sourceState: Mutex<ConfigurationSource>
    var source: ConfigurationSource { sourceState.withLock { $0 } }
    let makeLoop: @Sendable (RunSettings, LoopHooks) throws -> AgentLoop
    /// The sandbox the model narrowed this conversation to; it outlives loop rebuilds, not /new or /resume.
    let narrowing = SessionNarrowing()
    /// Reply-path metadata is cached per conversation, never shared across policies or projects.
    let replyPaths = ReplyPathExistence()
    /// What the person's `!` commands printed since their last message, which goes with the next one (note n56).
    let shellReports = Mutex<[String]>([])
    /// The sessions whose naming from their first request was tried already (note n60), so a turn does not ask again.
    let namingTried = Mutex<Set<String>>([])
    /// Approval questions waiting for an answer, the grants for this session, and where to ask (roadmap 0019).
    let approvals = Mutex(Approvals())
    let directory: SessionDirectory
    let current: Mutex<Current>
    let session = Mutex<SessionRecorder?>(nil)
    /// The file the next new session will be, named ahead so its colour holds from launch (roadmap 0164).
    let plannedSession = Mutex<String?>(nil)
    /// Launch consent is consumed once, not reused to authorize an account replacement later in this process.
    let destinationSelected = Mutex(false)
    /// Keeps the Mac awake while a turn or a job runs (`keepAwake`, roadmap 0090).
    let keepAwake: KeepAwake
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
    /// Where a settings change made during a turn is offered to it, for its next request (roadmap 0113).
    let handover = LoopHandover()
    /// The threads `/thread` started (roadmap 0194), and the jobs they are listed beside.
    let threads = ThreadTable()
    /// The goal `/goal` sets, judged when each run ends (roadmap 0227).
    let goal = GoalState()
    /// The status bar's git segment (roadmap 0186).
    let gitStatus = CoalescedRefresh()
    /// The `#` picker's pull requests and issues, and the branch's pull request (roadmap 0186).
    let forge = ForgeListing()
    /// The thread whose lane the screen shows, for `/reload` to show it again (roadmap 0195).
    let focusedThread = Mutex<String?>(nil)

    /// The settings in force, the loop built from them, and the last reload error shown.
    struct Current {
        var settings: RunSettings
        var loop: AgentLoop?
        /// Threads' loop when `threads.model` names another model (roadmap 0195); dropped with `loop`.
        var threadLoop: AgentLoop?
        /// Subagents' loops, by the definition they run as ("" for none) (roadmap 0063); dropped with `loop`.
        var subagentLoops: [String: AgentLoop] = [:]
        var shownError: String?
        /// A turn is running (roadmap 0127): a change made during it is offered to it (roadmap 0113).
        var turnRunning = false
        /// What waits for the running turn's end (roadmap 0113).
        var turnEndWaiters: [CheckedContinuation<Void, Never>] = []
    }

    /// - Parameters:
    ///   - directory: where a new session is created on the first prompt.
    ///   - resumed: a session already open, which prompts continue instead.
    ///   - settings: what the run starts with.
    ///   - source: where the settings come from, read again before each prompt, all or nothing.
    ///   - jobs: the jobs `/reload` must not orphan.
    ///   - mcp: the MCP servers, started with the settings and kept across loop rebuilds.
    ///   - grants: what the person allowed for the session before a reload (roadmap 0159).
    ///   - makeLoop: builds the loop for some settings, on the first prompt and after a change.
    init(
        directory: SessionDirectory,
        resumed: SessionRecorder? = nil,
        settings: RunSettings,
        source: ConfigurationSource,
        jobs: JobTable,
        mcp: MCPHub,
        grants: SessionGrants? = nil,
        makeLoop: @escaping @Sendable (RunSettings, LoopHooks) throws -> AgentLoop
    ) {
        sourceState = Mutex(source)
        self.jobs = jobs
        self.mcp = mcp
        self.makeLoop = makeLoop
        self.directory = directory
        current = Mutex(Current(settings: settings))
        session.withLock { $0 = resumed }
        _ = SessionTasks.follow(resumed, scope: settings.configuration.taskScope.value)
        keepAwake = KeepAwake(
            mode: settings.configuration.keepAwake.value,
            display: settings.configuration.keepDisplayAwake.value
        )
        Self.follow(jobs, with: keepAwake)
        jobs.keepFinished = settings.configuration.jobs.value.limit
        if let grants { approvals.withLock { $0.restore(grants) } }
    }

    /// What the screen shows first for a resumed session: its conversation, then its usage so far, which the
    /// status line keeps adding to.
    func history() -> [ConversationUpdate] {
        guard let tree = session.withLock({ $0?.tree }) else { return [contextUpdate()] }
        // With its threads' blocks where they started and merged (roadmap 0195).
        let branch = tree.activeBranch()
        let updates = replayed(branch, after: nil, placing: Self.threadBlocks(tree.threads, under: nil, on: branch))
        return updates + [.status(usage.withLock { $0.compact }), contextUpdate()]
    }

    func enqueue(_ text: String, id: Int, followUp: Bool) { enqueue(text, images: [], id: id, followUp: followUp) }

    func enqueue(_ text: String, images: [ToolImage], id: Int, followUp: Bool) {
        // A skill asked for during a turn is expanded as at a turn's start; a skill that cannot be loaded sends the message back to the
        // input. The queue attaches @server:uri, #t3 and #i2 when the loop takes it (0067, 0186).
        let update = approvals.withLock { $0.ask }
        guard let sent = expandingSkill(text, update: update ?? { _ in }) else {
            update?(.promptRefused(id: id))
            return
        }
        promptInput.withLock { $0 }?
            .append(
                QueuedPrompt(
                    id: id,
                    text: sent,
                    delivery: followUp ? .followUp : .steering,
                    images: images.map(\.part)
                )
            )
    }

    func sendCommandToBackground() -> Bool { jobs.sendForegroundToBackground() }

    func withdraw(_ id: Int) -> Bool {
        promptInput.withLock { $0 }?.withdraw(id: id) ?? false
    }

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        start(prompt, images: [], update: update)
    }

    func start(_ prompt: String, images: [ToolImage], update: @escaping @Sendable (ConversationUpdate) -> Void)
        -> Task<Void, Never>
    {
        // A message typed during the turn has its @server:uri read when the loop takes it, then #t3 and #i2, as at the turn's start.
        let input = PromptQueue { [mcp, threads, self] text in
            threads.attachReports(
                await self.attachingForgeReferences(
                    SessionTasks.attachReferences(await mcp.attachResources(self.attachingShellReports(text))),
                    update: update
                )
            )
        }
        promptInput.withLock { $0 = input }
        // Approval questions during this run go to this run's screen updates.
        approvals.withLock { $0.ask = update }
        return Task {
            self.beginTurn()
            defer { self.endTurn(update: update) }
            do {
                await self.refreshSettings(update: update)
                self.noticeUntrustedSkills(update: update)
                guard let expanded = self.expandingSkill(prompt, update: update) else {
                    update(.runEnded)
                    return
                }
                try await self.connectMCP(update: update)
                // Each @server:uri read from its server once it is connected (roadmap 0067), then #t3 and #i2 (0186).
                // A thread that ended since the last message: its answer goes with this one (roadmap 0194).
                let prompt = self.threads.attachReports(
                    await self.attachingForgeReferences(
                        SessionTasks.attachReferences(
                            await self.mcp.attachResources(self.attachingShellReports(expanded))
                        ),
                        update: update
                    )
                )
                let loop = try self.agentLoop()
                // A new session waits for how it is to be kept, when the screen is still asking (idea i1).
                if self.session.withLock({ $0 == nil }) { try await SessionKeyAccess.settled() }
                let recorder = try self.recorder()
                self.saveHeldIdeas(update: update)
                self.nameConversation(startingWith: prompt, update: update)
                try self.current.withLock { $0.settings }.record(in: recorder)
                try await loop.run(prompt, images: images.map(\.part), in: recorder, input: input) {
                    self.deliver($0, to: update)
                }
            } catch AgentError.promptBlocked(let reason) {
                // A hook kept the message out (roadmap 0192): nothing was recorded; it goes back to the input with the reason.
                update(.notice(reason, isError: true))
                update(.fillDraft(prompt))
                update(.returnQueuedPrompts)
            } catch {
                self.report(error, to: update)
                update(.returnQueuedPrompts)
            }
            update(.runEnded)
            self.refreshGitStatus(update)
            self.refreshForge(update)
        }
    }

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
        if case .compacted(let summary, _) = event {
            renameConversation(fromSummary: summary, update: update)
            // What a compaction folds away stays searchable: the index takes it now (t209).
            if let recorder = session.withLock({ $0 }) {
                Task.detached(priority: .utility) {
                    await SessionSearch.of(session: recorder.path).update(from: recorder)
                }
            }
        }
    }
}
