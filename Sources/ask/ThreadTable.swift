internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The threads `/thread` started (roadmap 0194): each one's session, the queue its lane's messages go to while it runs, and its state;
/// the answers of those that ended, waiting for the person's next message; and the jobs they are listed beside.
final class ThreadTable: Sendable {
    struct Thread {
        let name: String
        let prompt: String
        let recorder: SessionRecorder
        let started: ContinuousClock.Instant
        var state: RunnerInfo.State = .running
        var queue: PromptQueue?
        var task: Task<Void, Never>?
    }

    private struct State {
        var next = 1
        var nextPrompt = -1
        var threads: [String: Thread] = [:]
        var order: [String] = []
        var reports: [String] = []
        var jobs: [RunnerInfo] = []
    }

    private let state = Mutex(State())

    /// A new thread over `recorder`, named `thread-N`, running.
    func add(prompt: String, recorder: SessionRecorder) -> String {
        state.withLock { state in
            let name = "thread-\(state.next)"
            state.next += 1
            state.threads[name] = Thread(name: name, prompt: prompt, recorder: recorder, started: .now)
            state.order.append(name)
            return name
        }
    }

    func thread(_ name: String) -> Thread? { state.withLock { $0.threads[name] } }

    /// Thread `name` runs `task`, its lane's messages going to `queue`.
    func run(_ name: String, task: Task<Void, Never>, queue: PromptQueue) {
        state.withLock { state in
            state.threads[name]?.task = task
            state.threads[name]?.queue = queue
            state.threads[name]?.state = .running
        }
    }

    /// Thread `name`'s run ended as `outcome`; `report`, its answer under its name, goes with the person's next message.
    func ended(_ name: String, as outcome: RunnerInfo.State, report: String?) {
        state.withLock { state in
            state.threads[name]?.state = outcome
            state.threads[name]?.queue = nil
            state.threads[name]?.task = nil
            if let report { state.reports.append(report) }
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

    /// `text` with the answers of the threads that ended since the last message after it, each once.
    func attachReports(_ text: String) -> String {
        let reports = state.withLock { state in
            defer { state.reports = [] }
            return state.reports
        }
        return text + reports.joined()
    }

    func setJobs(_ jobs: [RunnerInfo]) { state.withLock { $0.jobs = jobs } }

    /// The jobs, then the threads in the order they were started.
    var runners: [RunnerInfo] {
        state.withLock { state in
            state.jobs
                + state.order.compactMap { name in
                    state.threads[name]
                        .map {
                            RunnerInfo(
                                name: $0.name,
                                detail: $0.prompt,
                                id: $0.name,
                                kind: .agent,
                                state: $0.state,
                                startedAt: $0.started
                            )
                        }
                }
        }
    }

    /// Stops every running thread and waits for each to end, as ask does with jobs when it quits.
    func stopAll() async {
        let tasks = state.withLock { $0.threads.values.compactMap(\.task) }
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }
}
