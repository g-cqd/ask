internal import Darwin
internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

internal import struct AskAgentCore.SandboxPolicy

/// One command, running in its own session, whose output is collected, streamed to a file, and waited on
/// (roadmap 0031, ADR-0027).
///
/// - Output the model has not seen yet is kept as a bounded head and tail, and handed over by ``takeOutput()``.
/// - Waiters register a condition the job evaluates itself as output arrives and when it ends: no polling, and
///   no closure crosses into the lock.
/// - Stopping cancels the task that runs the command; swift-subprocess then sends SIGTERM to the group, waits
///   two seconds, and sends SIGKILL.
public final class Job: Sendable {
    /// What a wait ended on.
    enum WaitResult: Sendable, Equatable {
        case found
        case ended
        case cancelled
    }

    public let id: String
    public let command: String
    /// Monotonic launch time, shared with the screen rather than restarted when its list opens.
    public let startedAt = ContinuousClock.now
    /// Where the whole output goes, if anywhere.
    let outputPath: String?

    struct Waiter {
        var needle: [UInt8]?
        var carry: [UInt8] = []
        let continuation: CheckedContinuation<WaitResult, Never>
    }

    struct State {
        var status = JobStatus.running
        var unread: OutputBuffer
        /// The last ``recentBytes`` of all output, seen or not: where a text a waiter looks for may have begun.
        var recent: [UInt8] = []
        var totalBytes = 0
        var totalLines = 0
        var file: FileDescriptor?
        var fileBytes = 0
        var input: AsyncStream<[UInt8]>.Continuation?
        var pid: pid_t?
        var task: Task<Void, Never>?
        var waiters: [Int: Waiter] = [:]
        var nextWaiter = 0
        var outputObservers: [Int: AsyncStream<Void>.Continuation] = [:]
        var nextOutputObserver = 0
    }

    /// How much recent output seeds a new waiter, so a text split across a report is still found.
    static let recentBytes = 4_096

    /// The largest output file kept for one command.
    static let maximumFileBytes = 64 << 20

    /// Internal only for Job's own extensions, which split it by behaviour; nothing else touches it.
    let state: Mutex<State>
    private let keeping: Int

    /// What the command is allowed to do; its output is explained against it when the sandbox refused something.
    let sandbox: SandboxPolicy

    private let watchdog: JobWatchdog?

    private init(
        id: String, command: String, outputPath: String?, keeping: Int, sandbox: SandboxPolicy, watchdog: JobWatchdog?
    ) {
        self.watchdog = watchdog
        self.sandbox = sandbox
        self.keeping = keeping
        self.id = id
        self.command = command
        self.outputPath = outputPath
        state = Mutex(State(unread: OutputBuffer(keeping: keeping)))
    }

    /// Starts a job.
    /// - Parameters:
    ///   - launch: what to run, and how.
    ///   - observe: sees every chunk of output, for tests.
    /// - Returns: the running job.
    static func start(_ launch: Launch, observe: @escaping @Sendable ([UInt8]) -> Void) -> Job {
        let job = Job(
            id: launch.id, command: launch.command, outputPath: launch.outputPath, keeping: launch.keeping,
            sandbox: launch.sandbox, watchdog: launch.watchdog)
        let (input, feed) = AsyncStream<[UInt8]>.makeStream()
        if !launch.keepsInputOpen { feed.finish() }
        let file = launch.outputPath.flatMap(JobProcess.createFile)
        job.state.withLock { state in
            state.input = launch.keepsInputOpen ? feed : nil
            state.file = file
        }
        let task = Task { await job.execute(JobProcess.configuration(launch), input: input, observe: observe) }
        job.state.withLock { $0.task = task }
        return job
    }

    private func execute(
        _ configuration: Configuration, input: AsyncStream<[UInt8]>, observe: @escaping @Sendable ([UInt8]) -> Void
    ) async {
        let ending: JobStatus
        do {
            let result = try await Subprocess.run(
                configuration, input: .inputWriter, output: .sequence, error: .combinedWithOutput
            ) { execution in
                self.state.withLock { $0.pid = execution.processIdentifier.value }
                // The job leads its own session, so its group is its process id.
                self.watchdog?.watch(execution.processIdentifier.value)
                let writer = execution.standardInputWriter
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await chunk in input { _ = try await writer.write(chunk) }
                        try await writer.finish()
                    }
                    for try await buffer in execution.standardOutput {
                        let bytes = buffer.bytes.withUnsafeBytes { Array($0) }
                        self.received(bytes)  // held first: an observer that acts on `bytes` finds them in the buffer
                        observe(bytes)
                    }
                    group.cancelAll()
                }
            }
            if Task.isCancelled {
                ending = .stopped
            } else {
                switch result.terminationStatus {
                    case .exited(let code): ending = .exited(Int(code))
                    case .signaled(let signal): ending = .signalled(Int(signal))
                }
            }
        } catch {
            ending = Task.isCancelled ? .stopped : .failedToStart(String(describing: error))
        }
        finish(ending)
    }

    // MARK: - Output

    private func received(_ bytes: [UInt8]) {
        let met: [CheckedContinuation<WaitResult, Never>] = state.withLock { state in
            state.unread.append(bytes)
            state.recent = Array((state.recent + bytes).suffix(Self.recentBytes))
            state.totalBytes += bytes.count
            for byte in bytes where byte == 0x0A { state.totalLines += 1 }
            if let file = state.file, state.fileBytes < Self.maximumFileBytes {
                let room = Self.maximumFileBytes - state.fileBytes
                let written = Array(bytes.prefix(room))
                if (try? file.writeAll(written)) == nil { state.fileBytes = Self.maximumFileBytes }
                state.fileBytes += written.count
            }
            for observer in state.outputObservers.values { observer.yield(()) }
            var met: [CheckedContinuation<WaitResult, Never>] = []
            for (key, var waiter) in state.waiters {
                guard let needle = waiter.needle else { continue }
                let window = waiter.carry + bytes
                if window.firstRange(of: needle) != nil {
                    met.append(waiter.continuation)
                    state.waiters[key] = nil
                } else {
                    waiter.carry = Array(window.suffix(Swift.max(0, needle.count - 1)))
                    state.waiters[key] = waiter
                }
            }
            return met
        }
        for continuation in met { continuation.resume(returning: .found) }
    }

    private func finish(_ ending: JobStatus) {
        if let pid = state.withLock({ $0.pid }) { watchdog?.release(pid) }
        let (waiting, observers) = state.withLock { state in
            state.status = ending
            let observers = Array(state.outputObservers.values)
            state.outputObservers.removeAll()
            state.input?.finish()
            state.input = nil
            if let file = state.file { _ = try? file.close() }
            state.file = nil
            defer { state.waiters.removeAll() }
            return (state.waiters.values.map(\.continuation), observers)
        }
        for observer in observers { observer.finish() }
        for continuation in waiting { continuation.resume(returning: .ended) }
    }

    /// The output the model has not seen yet, which counts as seen from now on.
    func takeOutput() -> String {
        state.withLock { state in
            let text = state.unread.text
            state.unread = OutputBuffer(keeping: keeping)
            return text
        }
    }

    public var status: JobStatus { state.withLock { $0.status } }

    /// Every byte and line the command printed, for deciding whether its file is worth keeping.
    var printed: (bytes: Int, lines: Int) { state.withLock { ($0.totalBytes, $0.totalLines) } }

    /// Removes the output file: for a command whose result already held all of it.
    func discardFile() {
        guard let outputPath else { return }
        _ = unlink(outputPath)
    }

    // MARK: - Input and stopping

    /// Sends `bytes` to standard input.
    /// - Returns: false when input is closed or the job has ended.
    func write(_ bytes: [UInt8]) -> Bool {
        state.withLock { state in
            guard let input = state.input else { return false }
            if case .terminated = input.yield(bytes) { return false }
            return true
        }
    }

    /// Closes standard input, so the command sees end-of-file.
    func closeInput() {
        state.withLock { state in
            state.input?.finish()
            state.input = nil
        }
    }

    /// Asks the job to stop; ``ended()`` says when it has.
    func stop() { state.withLock { $0.task }?.cancel() }

    /// Signals the job's whole process group at once, for exit paths that cannot wait.
    func signalGroup(_ signal: Int32) {
        guard let pid = state.withLock({ $0.status == .running ? $0.pid : nil }) else { return }
        kill(-pid, signal)
    }
}
