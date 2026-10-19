/// The interactive screen's conversation: each prompt is a run of the agent loop in one session.

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
/// Configuration is read again before every prompt (ADR-0031). A valid change takes effect on that prompt and
/// is reported; an invalid one is reported once and the previous settings stay.
final class AgentConversation: Conversation {
    private let reload: @Sendable () throws -> RunSettings
    private let makeLoop: @Sendable (RunSettings) throws -> AgentLoop
    private let directory: SessionDirectory
    private let current: Mutex<Current>
    private let session = Mutex<SessionRecorder?>(nil)
    private let usage = Mutex(UsageTotals())

    /// The settings in force, the loop built from them, and the last reload error shown.
    private struct Current {
        var settings: RunSettings
        var loop: AgentLoop?
        var shownError: String?
    }

    /// - Parameters:
    ///   - directory: where a new session is created on the first prompt.
    ///   - resumed: a session already open, which prompts continue instead.
    ///   - settings: what the run starts with.
    ///   - reload: reads the settings again, all or nothing.
    ///   - makeLoop: builds the loop for some settings, on the first prompt and after a change.
    init(
        directory: SessionDirectory, resumed: SessionRecorder? = nil, settings: RunSettings,
        reload: @escaping @Sendable () throws -> RunSettings,
        makeLoop: @escaping @Sendable (RunSettings) throws -> AgentLoop
    ) {
        self.reload = reload
        self.makeLoop = makeLoop
        self.directory = directory
        current = Mutex(Current(settings: settings))
        session.withLock { $0 = resumed }
    }

    /// Reads the configuration again and, when it changed, tells the screen what changed. The loop is rebuilt
    /// on the next use.
    private func refreshSettings(update: @Sendable (ConversationUpdate) -> Void) {
        let fresh: RunSettings
        do {
            fresh = try reload()
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
    }

    /// What the screen shows first for a resumed session: its conversation, then its usage so far, which the
    /// status line keeps adding to.
    func history() -> [ConversationUpdate] {
        guard let tree = session.withLock({ $0?.tree }) else { return [] }
        var updates: [ConversationUpdate] = []
        for step in SessionReplay.steps(tree.activeBranch()) {
            switch step {
                case .prompt(let text): updates.append(.userPrompt(text))
                case .event(let event):
                    if let spent = event.usage { usage.withLock { $0.add(spent) } }
                    if let shown = Self.update(for: event) { updates.append(shown) }
            }
        }
        return updates + [.status(usage.withLock { $0.summary })]
    }

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        Task {
            do {
                self.refreshSettings(update: update)
                let loop = try self.agentLoop()
                let recorder = try self.recorder()
                try await loop.run(prompt, in: recorder) { event in
                    if let spent = event.usage {
                        let summary = self.usage.withLock { totals in
                            totals.add(spent)
                            return totals.summary
                        }
                        update(.status(summary))
                    }
                    if let shown = Self.update(for: event) { update(shown) }
                }
            } catch AgentError.cancelled {
                update(.notice("Aborted. Results already known were kept.", isError: false))
            } catch {
                update(.notice("ask: \(error)", isError: true))
            }
            update(.runEnded)
        }
    }

    private func agentLoop() throws -> AgentLoop {
        try current.withLock { current throws -> AgentLoop in
            if let existing = current.loop { return existing }
            let created = try makeLoop(current.settings)
            current.loop = created
            return created
        }
    }

    /// The session, created on the first prompt so that opening and closing ask leaves no empty sessions.
    private func recorder() throws -> SessionRecorder {
        try session.withLock { existing throws -> SessionRecorder in
            if let existing { return existing }
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
            let created = SessionRecorder(try SessionFile.create(at: FilePath(directory.newSessionPath())))
            existing = created
            return created
        }
    }

    private static func update(for event: AgentEvent) -> ConversationUpdate? {
        switch event {
            case .model(.textDelta(_, let text)): return .assistantText(text)
            case .toolStarted(_, let name, let input):
                return .toolStarted(name: name, summary: toolSummary(name: name, input: input))
            case .toolFinished(_, _, let output):
                let last = output.content.split(separator: "\n").last.map(String.init) ?? ""
                return .toolFinished(output.isError ? .failed(last) : .succeeded)
            case .repaired(let repairs):
                return .notice("Repaired the context before this turn: \(repairs)", isError: false)
            case .compacted, .compactionFailed:
                return compactionNotice(event).map { .notice($0, isError: false) }
            case .continuedAtOutputLimit:
                return .notice("The response hit the output limit; asking the model to continue.", isError: false)
            case .retrying(let attempt, let total, let delay, let reason):
                return .notice(retryNotice(attempt: attempt, of: total, delay: delay, reason: reason), isError: false)
            default: return nil
        }
    }
}

/// The interactive screen in the working directory.
func runInteractive(source: ConfigurationSource, settings: RunSettings, session choice: SessionChoice) async {
    let workingDirectory = FileManager.default.currentDirectoryPath
    let directory = SessionDirectory(project: workingDirectory)
    var notices: [String] = []
    let resumed = choice.open(in: directory) { notices.append($0) }
    if let resumed { notices.append("Resumed session \((resumed.path as NSString).lastPathComponent)") }
    let jobs = JobTable()
    do {
        let files = instructionFiles(workingDirectory: workingDirectory)
        let conversation = AgentConversation(
            directory: directory, resumed: resumed, settings: settings, reload: { try source.load() },
            makeLoop: { settings in
                try makeLoop(
                    model: settings.model, workingDirectory: workingDirectory, instructions: files,
                    limits: settings.limits, jobs: jobs, transport: URLSessionTransport())
            })
        // A shutdown signal exits at once from the screen, so its jobs are signalled there; a normal quit
        // stops them gracefully below.
        try await runInteractiveScreen(
            conversation: conversation, label: modelLabel(settings.model), history: conversation.history(),
            notices: notices + settings.description + describe(files), beforeSignalExit: { jobs.terminateAllNow() })
        await jobs.stopAll()
    } catch {
        await jobs.stopAll()
        // The screen has already restored the terminal by the time an error reaches here.
        fail("ask: \(error)", code: 70)
    }
}
