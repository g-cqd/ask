internal import AskAgentCore
internal import Foundation
internal import Synchronization

/// The jobs of one ask process, shared by `bash`, `wait`, `job_input` and `job_stop` (ADR-0027).
///
/// Jobs belong to the process, not to a turn: a server started in one turn is waited on in the next. ask
/// stops them all when it exits by any path it can see; a SIGKILL of ask is the one it cannot, and the ``JobWatchdog`` covers it
/// (ADR-0079).
public final class JobTable: Sendable {
    private let jobs = Mutex<[String: Job]>([:])
    private let counter = Atomic<Int>(0)
    private let displayIDs = Mutex(JobDisplayIDs())
    private let observers = Mutex<[Int: AsyncStream<[JobSummary]>.Continuation]>([:])
    private let nextObserver = Atomic<Int>(0)
    /// Stops the jobs' groups if ask is killed, which nothing in ask can observe (ADR-0079).
    let watchdog = JobWatchdog()
    /// Distinguishes this process's output files from another ask's in the same directory.
    private let filePrefix: String

    /// The environment commands inherit, before a run's policy takes from it what it withholds (ADR-0106).
    private let environment: [String: String]

    /// An empty table whose commands inherit ask's own environment, less what a run's policy withholds.
    public convenience init() { self.init(environment: ProcessInfo.processInfo.environment) }

    /// An empty table whose commands inherit `environment`: ask passes the one it was launched with, a test chooses its own.
    public init(environment: [String: String]) {
        self.environment = environment
        filePrefix = "\(Int(Date().timeIntervalSince1970))-\(getpid())"
    }

    /// Shell selection belongs to the shell tool; internal POSIX job scripts keep their bash default.
    func commandShell(_ requested: String?, in context: ToolContext) -> String {
        let candidate = requested ?? context.commandEnvironment.filtered(environment)["SHELL"]
        if let candidate, candidate.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/bin/bash"
    }

    /// Starts `command` as a new job.
    /// - Parameters:
    ///   - command: the bash command.
    ///   - context: where it runs, and where its output file goes.
    ///   - keepsInputOpen: whether standard input stays open.
    ///   - keeping: how many bytes of unseen output to keep at each end.
    ///   - shell: the shell binary to use, or nil for default.
    ///   - observe: sees every chunk of output, for tests.
    /// - Returns: the running job.
    func start(
        _ command: String, in context: ToolContext, keepsInputOpen: Bool, keeping: Int,
        shell: String? = nil,
        observe: @escaping @Sendable ([UInt8]) -> Void
    ) -> Job {
        let number = counter.wrappingAdd(1, ordering: .relaxed).newValue
        let id = "job-\(number)"
        let path = context.outputDirectory.map { $0 + "/\(filePrefix)-\(number).log" }
        let job = Job.start(
            Job.Launch(
                id: id, displayID: displayIDs.withLock { $0.next() }, command: command,
                workingDirectory: context.workingDirectory, outputPath: path,
                keepsInputOpen: keepsInputOpen, keeping: keeping, sandbox: context.sandbox, watchdog: watchdog,
                environment: context.commandEnvironment.filtered(environment), shell: shell),
            observe: observe)
        jobs.withLock { $0[id] = job }
        notifyObservers()
        // The table learns of an ending the way `job_stop` does, by waiting for it, so nothing polls.
        Task { [weak self] in
            await job.ended()
            self?.notifyObservers()
        }
        return job
    }

    /// The job named `id`.
    func job(_ id: String) -> Job? {
        jobs.withLock { jobs in
            jobs[id] ?? jobs.values.first { $0.displayID == (id.hasPrefix("#") ? String(id.dropFirst()) : id) }
        }
    }

    /// The jobs still running, by name.
    public var running: [String] {
        jobs.withLock { $0.values.filter { $0.status == .running }.map(\.id).sorted() }
    }

    /// The jobs still running, in the order they started.
    public var summaries: [JobSummary] {
        jobs.withLock {
            $0.values.filter { $0.status == .running }
                .sorted { Self.number($0.id) < Self.number($1.id) }
                .map { JobSummary(id: $0.id, command: $0.command, startedAt: $0.startedAt, displayID: $0.displayID) }
        }
    }

    /// The running jobs now, then again each time one starts or ends. A slow reader sees the newest list, not every list.
    public func changes() -> AsyncStream<[JobSummary]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let key = nextObserver.wrappingAdd(1, ordering: .relaxed).newValue
            observers.withLock { $0[key] = continuation }
            continuation.onTermination = { [weak self] _ in self?.observers.withLock { $0[key] = nil } }
            continuation.yield(summaries)
        }
    }

    private func notifyObservers() {
        let list = summaries
        observers.withLock { for continuation in $0.values { continuation.yield(list) } }
    }

    private static func number(_ id: String) -> Int { Int(id.dropFirst(4)) ?? 0 }

    /// Stops every running job and waits for each to end: SIGTERM to its group, then SIGKILL after two
    /// seconds.
    public func stopAll() async {
        let all = jobs.withLock { Array($0.values) }
        for job in all { job.stop() }
        for job in all { await job.ended() }
    }

    /// Signals every running job's group at once, for an exit that cannot wait: SIGTERM, then SIGKILL.
    public func terminateAllNow() {
        let all = jobs.withLock { Array($0.values) }
        for job in all { job.signalGroup(SIGTERM) }
        for job in all { job.signalGroup(SIGKILL) }
    }
}
