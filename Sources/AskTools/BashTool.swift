public import AskAI
public import AskAgentCore
internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

/// `bash`: runs a command in the working directory and returns its combined output and how it ended.
///
/// - Every command is a ``Job`` in its own session, so teardown reaches every process it started and never ask's
///   own process group. Teardown on timeout or abort: SIGTERM to the group, a grace period, then SIGKILL.
/// - Without `yield_seconds`, standard input is closed, so a command that waits for input ends instead of
///   hanging, and the command is stopped at its timeout.
/// - With `yield_seconds`, a command still running then is left running as a job, with standard input open,
///   controlled with `job` (ADR-0027).
/// - Output is kept as a 512 KiB head and tail. The whole of it goes to a file when the context has an output
///   directory, and the file is kept when the result would be cut, so the model can read what was cut.
public struct BashTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let command: String
        let shell: String?
        let timeoutSeconds: Int?
        let waitForOutput: String?
        let yieldSeconds: Int?
        let waitForPort: Int?
        let waitForFile: String?
        enum CodingKeys: String, CodingKey {
            case command
            case timeoutSeconds = "timeout_seconds"
            case yieldSeconds = "yield_seconds"
            case waitForOutput = "wait_for_output"
            case waitForPort = "wait_for_port"
            case waitForFile = "wait_for_file"
            case shell
        }
    }

    /// What tests observe, through an internal hook.
    enum Event: Sendable {
        case output([UInt8])
    }

    public static let defaultTimeout = 120
    public static let maximumTimeout = 600
    /// How a command stopped for its deadline ends its output.
    static let timedOutMark = "[timed out after"
    /// How a command stopped by the person ends its output.
    static let abortedMark = "[aborted; the command and its children were stopped]"
    /// How a command that could not start is told.
    static let startFailure = "bash could not start: "
    static let keptBytes = 512 << 10

    public let definition: ToolDefinition

    private let access: JobAccess
    private let observe: @Sendable (Event) -> Void

    /// A bash tool with its own job table, timing out on the continuous clock.
    public init() { self.init(jobs: JobTable()) }

    /// A bash tool whose jobs live in `jobs`, shared with the job tools.
    public init(jobs: JobTable, commandEnvironment: CommandEnvironment = .inherit) {
        self.init(jobs: jobs, clock: ContinuousClock(), commandEnvironment: commandEnvironment) { _ in }
    }

    init(
        jobs: JobTable = JobTable(),
        clock: any Clock<Duration>,
        commandEnvironment: CommandEnvironment = .inherit,
        observe: @escaping @Sendable (Event) -> Void
    ) {
        access = JobAccess(jobs: jobs, clock: clock)
        definition = Self.makeDefinition(shell: jobs.commandShell(nil, policy: commandEnvironment))
        self.observe = observe
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let readiness = try ShellReadiness.select(
            output: arguments.waitForOutput,
            port: arguments.waitForPort,
            file: arguments.waitForFile,
            in: context
        )
        if let shell = arguments.shell, !JobTable.isShell(shell) {
            throw ToolFailure(
                "shell must name a shell's absolute path, such as /bin/bash; the command to run goes in command."
            )
        }
        let shell = access.jobs.commandShell(arguments.shell, in: context)
        let checked = await CommandCheck.check(
            arguments.command,
            shell: shell,
            path: access.jobs.visiblePath(in: context)
        )
        if let syntaxError = checked.syntaxError {
            throw ToolFailure("The command does not parse in \(shell), so it was not run:\n\(syntaxError)")
        }
        let yield = arguments.yieldSeconds.map { Swift.min(Swift.max(1, $0), Self.maximumTimeout) }
        let timeout = Swift.min(Swift.max(1, arguments.timeoutSeconds ?? Self.defaultTimeout), Self.maximumTimeout)
        let limit = readiness == nil ? (yield ?? timeout) : timeout
        let observe = observe
        let job = access.jobs.start(
            arguments.command,
            in: context,
            keepsInputOpen: yield != nil || readiness != nil,
            keeping: Self.keptBytes,
            shell: shell
        ) {
            observe(.output($0))
        }
        do {
            let clock = access.clock
            // The person may send the command to the background while the model waits on it (roadmap 0173).
            let outcome =
                try await access.jobs.foreground.race {
                    try await JobWaiting.wait(for: job, readiness: readiness, seconds: limit, clock: clock, in: context)
                } ?? .backgrounded
            var result = await Self.output(of: outcome, job: job, readiness: readiness, yield: yield, limit: limit)
            // Told when the command failed, where they may say why; a command that succeeded needs no lint.
            if result.isError, !checked.findings.isEmpty {
                result.content += "\n[shellcheck] " + checked.findings.joined(separator: "\n[shellcheck] ")
            }
            return result
        } catch {
            job.stop()
            await job.ended()
            // The wait throws only ToolFailure; the race around it widens the type, not what it throws.
            throw error as? ToolFailure ?? ToolFailure("The command's wait failed: \(error)")
        }
    }

    /// What the call returns once its wait is over: the output of a command that ended, a job still running in the background,
    /// or an error for one that was stopped.
    private static func output(
        of outcome: JobWaiting.Outcome,
        job: Job,
        readiness: ShellReadiness?,
        yield: Int?,
        limit: Int
    ) async -> ToolOutput {
        switch outcome {
            case .found where job.status != .running: return Self.finished(job)
            case .found: return Self.running(job, "[\(job.id) \(readiness?.headline ?? "ready"); still running]")
            case .ended: return Self.finished(job)
            case .backgrounded where job.status != .running: return Self.finished(job)
            case .backgrounded:
                return Self.running(
                    job,
                    "[sent to the background by the person as \(job.id)\(JobWaiting.fileNote(job)); display [#\(job.displayID)]; "
                        + "it goes on; use job to inspect, send input, or stop]"
                )
            case .timedOut where readiness == nil && yield != nil:
                return Self.running(
                    job,
                    "[still running as \(job.id) after \(limit) s\(JobWaiting.fileNote(job)); "
                        + "display [#\(job.displayID)]; use job to inspect, send input, or stop]"
                )
            case .timedOut, .cancelled:
                job.stop()
                await job.ended()
                return .error(
                    Self.body(job.takeOutput())
                        + (outcome == .cancelled
                            ? Self.abortedMark
                            : "\(Self.timedOutMark) \(limit) s; the command and its children were stopped]")
                )
        }
    }

    /// A command left running as a job: its output so far, then `note`.
    private static func running(_ job: Job, _ note: String) -> ToolOutput {
        job.markBackgrounded()
        return ToolOutput(body(job.takeOutput()) + note, backgroundJob: job.id)
    }

    /// The result of a command that ended: its output, where the whole of it is if that was too long, and
    /// how it ended.
    static func finished(_ job: Job) -> ToolOutput {
        let printed = job.printed
        let cut = printed.bytes > OutputCap.standard.maximumBytes || printed.lines >= OutputCap.standard.maximumLines
        if !cut { job.discardFile() }
        let output = job.takeOutput()
        let body = body(output) + (cut ? JobWaiting.fileLine(job) : "") + sandboxNote(for: job, output: output)
        switch job.status {
            case .exited(0): return ToolOutput(body + "[exit 0]")
            case .failedToStart(let reason): return .error(Self.startFailure + reason)
            case let status: return .error(body + "[\(status)]")
        }
    }

    /// A note only for a program that starts a sandbox of its own (SwiftPM, for a manifest it has not cached): Seatbelt does not nest,
    /// and the way out is a flag that is the program's, so naming it costs the model nothing about this run's policy. A refused command
    /// gets no note at all: the operating system's own "Operation not permitted" is already in the output, and what protects what
    /// stays with the user (ADR-0115).
    static func sandboxNote(for job: Job, output: String) -> String {
        guard !job.sandbox.isUnrestricted, output.contains("sandbox_apply: Operation not permitted") else { return "" }
        return nestedSandboxNote
    }

    static let nestedSandboxNote =
        "[A program in this command tried to start a sandbox of its own, which is not available here; "
        + "if it has a --disable-sandbox option, use it.]\n"

    static func body(_ text: String) -> String { text.isEmpty ? "" : (text.hasSuffix("\n") ? text : text + "\n") }
}
