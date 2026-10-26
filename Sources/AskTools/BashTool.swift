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
///   for `wait`, `job_input` and `job_stop` (ADR-0027).
/// - Output is kept as a 512 KiB head and tail. The whole of it goes to a file when the context has an output
///   directory, and the file is kept when the result would be cut, so the model can read what was cut.
public struct BashTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let command: String
        let timeoutSeconds: Int?
        let yieldSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case command
            case timeoutSeconds = "timeout_seconds"
            case yieldSeconds = "yield_seconds"
        }
    }

    /// What tests observe, through an internal hook.
    enum Event: Sendable {
        case output([UInt8])
    }

    public static let defaultTimeout = 120
    public static let maximumTimeout = 600
    static let keptBytes = 512 << 10

    public let definition = ToolDefinition(
        name: "bash",
        description: """
            Run a bash command in the working directory. Returns combined stdout and stderr and the exit status. \
            Without yield_seconds, standard input is closed and the command is stopped after timeout_seconds \
            (default 120, at most 600). With yield_seconds, a command still running after that many seconds keeps \
            running as a job, with standard input open: use it for servers, watchers and long builds, then wait, \
            job_input and job_stop. A result too long to show names a file holding the whole output.
            """
    ) {
        ToolProperty.string("command")
        ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600).optional
        ToolProperty.integer("yield_seconds", minimum: 1, maximum: 600).optional
        SandboxRequest.property
    }

    private let access: JobAccess
    private let observe: @Sendable (Event) -> Void

    /// A bash tool with its own job table, timing out on the continuous clock.
    public init() { self.init(jobs: JobTable()) }

    /// A bash tool whose jobs live in `jobs`, shared with the job tools.
    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) { _ in } }

    init(jobs: JobTable = JobTable(), clock: any Clock<Duration>, observe: @escaping @Sendable (Event) -> Void) {
        access = JobAccess(jobs: jobs, clock: clock)
        self.observe = observe
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let yield = arguments.yieldSeconds.map { Swift.min(Swift.max(1, $0), Self.maximumTimeout) }
        let limit =
            yield ?? Swift.min(Swift.max(1, arguments.timeoutSeconds ?? Self.defaultTimeout), Self.maximumTimeout)
        let observe = observe
        let job = access.jobs.start(
            arguments.command, in: context, keepsInputOpen: yield != nil, keeping: Self.keptBytes
        ) { observe(.output($0)) }
        switch await JobWaiting.wait(for: job, needle: nil, seconds: limit, clock: access.clock) {
            case .found, .ended:
                return Self.finished(job)
            case .timedOut where yield != nil:
                let shown = job.takeOutput()
                return ToolOutput(
                    (shown.isEmpty ? "" : shown.hasSuffix("\n") ? shown : shown + "\n")
                        + "[still running as \(job.id) after \(limit) s\(JobWaiting.fileNote(job)); "
                        + "use wait, job_input or job_stop]")
            case .timedOut, .cancelled:
                let aborted = Task.isCancelled
                job.stop()
                await job.ended()
                let body = Self.body(job.takeOutput())
                return .error(
                    body
                        + (aborted
                            ? "[aborted; the command and its children were stopped]"
                            : "[timed out after \(limit) s; the command and its children were stopped]"))
        }
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
            case .failedToStart(let reason): return .error("bash could not start: \(reason)")
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
