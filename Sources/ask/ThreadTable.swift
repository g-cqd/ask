internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The threads `/thread` started (roadmaps 0194, 0195): each one's session, the queue its lane's messages go to while it runs, its state
/// and how its last run ended; the summaries merged into each conversation, waiting for what is sent to it next; and the jobs they are
/// listed beside.
final class ThreadTable: Sendable {
    struct Thread {
        let name: String
        let prompt: String
        let recorder: SessionRecorder
        let started: ContinuousClock.Instant
        /// The thread it was forked from, which lists it under itself and receives its summary; nil for main's.
        var parent: String?
        var state: RunnerInfo.State = .running
        /// How its last run ended; nil while one runs.
        var outcome: RunnerInfo.State?
        var queue: PromptQueue?
        var task: Task<Void, Never>?
        /// How many of its questions wait on the person; while any does, it is listed as waiting (roadmap 0195).
        var asking = 0
        /// The summaries of the threads merged into it, for what it is sent next or for its own summary.
        var reports: [String] = []
        /// What it is called where it is shown: the on-device model's name or the person's; its id, `thread-N`, when none.
        var title: String?
    }

    struct State {
        var next = 1
        var nextPrompt = -1
        var threads: [String: Thread] = [:]
        var order: [String] = []
        /// The summaries merged into main.
        var reports: [String] = []
        var jobs: [RunnerInfo] = []
        var quitting = false
        /// Threads stopped together (a session switch, or a stop with its threads): they are settled as one, not each on its own.
        var holding: Set<String> = []
        /// Subagents (roadmap 0063), and the `agent` calls waiting for their reports.
        var subagents: Set<String> = []
        var subagentDefinitions: [String: AgentDefinition] = [:]
        var waiters: [String: CheckedContinuation<String, Never>] = [:]
    }

    /// Internal, for the queries in ThreadTable+Tree.swift.
    let state = Mutex(State())

    /// A new thread over `recorder`, named `thread-N`, running, under `parent` when it was forked from that thread.
    func add(prompt: String, recorder: SessionRecorder, parent: String? = nil) -> String {
        state.withLock { state in
            let name = "thread-\(state.next)"
            state.next += 1
            state.threads[name] = Thread(name: name, prompt: prompt, recorder: recorder, started: .now, parent: parent)
            state.order.append(name)
            return name
        }
    }

    func thread(_ name: String) -> Thread? { state.withLock { $0.threads[name] } }

    /// The name the next thread is given, for the `thread.start` hook point.
    var nextName: String { state.withLock { "thread-\($0.next)" } }

    /// Thread `name` runs `task`, its lane's messages going to `queue`.
    func run(_ name: String, task: Task<Void, Never>, queue: PromptQueue) {
        state.withLock { state in
            state.threads[name]?.task = task
            state.threads[name]?.queue = queue
            state.threads[name]?.state = .running
            state.threads[name]?.outcome = nil
        }
    }

    /// Thread `name`'s run ended as `outcome`.
    func ended(_ name: String, as outcome: RunnerInfo.State) {
        state.withLock { state in
            state.threads[name]?.state = outcome
            state.threads[name]?.outcome = outcome
            state.threads[name]?.queue = nil
            state.threads[name]?.task = nil
        }
    }

    func setState(_ name: String, _ new: RunnerInfo.State) { state.withLock { $0.threads[name]?.state = new } }

    /// Whether a thread under `name` has not merged yet: running, waiting, held or ended unmerged. It holds `name`'s merge.
    func hasUnmerged(under name: String) -> Bool {
        state.withLock { state in state.threads.values.contains { $0.parent == name && $0.state != .merged } }
    }

    /// One more of thread `name`'s questions waits on the person (`began`), or one is settled. Listed as waiting while any does.
    func asking(_ name: String, began: Bool) {
        state.withLock { state in
            guard var thread = state.threads[name] else { return }
            thread.asking = Swift.max(0, thread.asking + (began ? 1 : -1))
            if thread.state == .running || thread.state == .waitingForApproval {
                thread.state = thread.asking > 0 ? .waitingForApproval : .running
            }
            state.threads[name] = thread
        }
    }

    /// Steers a running thread with `text`; false when it is not running, and the message is its next run's.
    func steer(_ name: String, with text: String) -> Bool {
        state.withLock { state in
            guard let queue = state.threads[name]?.queue else { return false }
            queue.append(QueuedPrompt(id: state.nextPrompt, text: text))
            state.nextPrompt -= 1
            return true
        }
    }

    /// Keeps `report`, a merged thread's summary, for `owner`: a thread, or main when nil.
    func addReport(_ report: String, to owner: String?) {
        state.withLock { state in
            if let owner { state.threads[owner]?.reports.append(report) } else { state.reports.append(report) }
        }
    }

    /// The summaries merged into `owner` (main when nil) since they were last taken, each once.
    func takeReports(for owner: String? = nil) -> [String] {
        state.withLock { state in
            if let owner {
                defer { state.threads[owner]?.reports = [] }
                return state.threads[owner]?.reports ?? []
            }
            defer { state.reports = [] }
            return state.reports
        }
    }

    /// `text` with the summaries merged into `owner` (main when nil) after it, each once.
    func attachReports(_ text: String, for owner: String? = nil) -> String { text + takeReports(for: owner).joined() }

    func setJobs(_ jobs: [RunnerInfo]) { state.withLock { $0.jobs = jobs } }

    /// The jobs, then the threads in the order they were started.
    var runners: [RunnerInfo] {
        state.withLock { state in
            state.jobs
                + state.order.compactMap { name in
                    state.threads[name]
                        .map {
                            RunnerInfo(
                                name: $0.title ?? $0.name,
                                detail: $0.prompt,
                                id: $0.name,
                                parentID: $0.parent,
                                kind: .agent,
                                state: $0.state,
                                startedAt: $0.started
                            )
                        }
                }
        }
    }

    /// Whether thread `name` is still the one over `recorder`: a run stopped by a session switch must not touch the thread that took its
    /// name in the session switched to.
    func owns(_ name: String, _ recorder: SessionRecorder) -> Bool {
        state.withLock { $0.threads[name].map { $0.recorder === recorder } ?? false }
    }

    /// Forgets every thread and what was merged into main, stopping the runs, for another session's threads (roadmap 0195).
    func reset() {
        let tasks = state.withLock { state in
            defer {
                state.threads = [:]
                state.order = []
                state.reports = []
                state.holding = []
                state.subagents = []
                state.subagentDefinitions = [:]
                state.next = 1
            }
            return state.threads.values.compactMap(\.task)
        }
        for task in tasks { task.cancel() }
        releaseWaiters()
    }

    /// A thread of the session resumed, ended as `state` (merged, or stopped and never restarted), its name kept.
    func restore(
        _ name: String,
        prompt: String,
        parent: String?,
        recorder: SessionRecorder,
        state ended: RunnerInfo.State
    ) {
        state.withLock { state in
            var thread = Thread(name: name, prompt: prompt, recorder: recorder, started: .now, parent: parent)
            thread.state = ended
            thread.outcome = ended
            state.threads[name] = thread
            state.order.append(name)
            if let number = Int(name.dropFirst("thread-".count)) { state.next = Swift.max(state.next, number + 1) }
        }
    }

    /// Whether ask is quitting: a thread stopped by it is left unmerged, and asks nothing.
    var isQuitting: Bool { state.withLock { $0.quitting } }

    /// Whether thread `name` is settled with others it was stopped with, not on its own.
    func isHeldTogether(_ name: String) -> Bool { state.withLock { $0.holding.contains(name) } }

    /// Stops `names` together and waits for their runs to end; while `holding`, none of them is settled on its own.
    func stop(_ names: [String], holding: Bool) async {
        let tasks = state.withLock { state in
            if holding { state.holding.formUnion(names) }
            return names.compactMap { state.threads[$0]?.task }
        }
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    /// Lets `names` be settled on their own again.
    func release(_ names: [String]) { state.withLock { $0.holding.subtract(names) } }

    /// Stops every thread at work for a session switch, leaving them unmerged: they are the old session's.
    func stopForSwitch() async {
        let names = state.withLock { Array($0.threads.keys) }
        await stop(names, holding: true)
    }

    /// Stops every running thread and waits for each to end, as ask does with jobs when it quits.
    func stopAll() async {
        let tasks = state.withLock { state in
            state.quitting = true
            return state.threads.values.compactMap(\.task)
        }
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }
}
