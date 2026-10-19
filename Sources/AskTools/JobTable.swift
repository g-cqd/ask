internal import AskAgentCore
internal import Foundation
internal import Synchronization

/// The jobs of one ask process, shared by `bash`, `wait`, `job_input` and `job_stop` (ADR-0027).
///
/// Jobs belong to the process, not to a turn: a server started in one turn is waited on in the next. ask
/// stops them all when it exits by any path it can see; a SIGKILL of ask is the one it cannot (diary 12).
public final class JobTable: Sendable {
    private let jobs = Mutex<[String: Job]>([:])
    private let counter = Atomic<Int>(0)
    /// Distinguishes this process's output files from another ask's in the same directory.
    private let filePrefix: String

    /// An empty table.
    public init() {
        filePrefix = "\(Int(Date().timeIntervalSince1970))-\(getpid())"
    }

    /// Starts `command` as a new job.
    /// - Parameters:
    ///   - command: the bash command.
    ///   - context: where it runs, and where its output file goes.
    ///   - keepsInputOpen: whether standard input stays open.
    ///   - keeping: how many bytes of unseen output to keep at each end.
    ///   - observe: sees every chunk of output, for tests.
    /// - Returns: the running job.
    func start(
        _ command: String, in context: ToolContext, keepsInputOpen: Bool, keeping: Int,
        observe: @escaping @Sendable ([UInt8]) -> Void
    ) -> Job {
        let number = counter.wrappingAdd(1, ordering: .relaxed).newValue
        let id = "job-\(number)"
        let path = context.outputDirectory.map { $0 + "/\(filePrefix)-\(number).log" }
        let job = Job.start(
            Job.Launch(
                id: id, command: command, workingDirectory: context.workingDirectory, outputPath: path,
                keepsInputOpen: keepsInputOpen, keeping: keeping),
            observe: observe)
        jobs.withLock { $0[id] = job }
        return job
    }

    /// The job named `id`.
    func job(_ id: String) -> Job? { jobs.withLock { $0[id] } }

    /// The jobs still running, by name.
    public var running: [String] {
        jobs.withLock { $0.values.filter { $0.status == .running }.map(\.id).sorted() }
    }

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
