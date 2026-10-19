public import AskAI
public import AskAgentCore

/// `wait`: blocks until a job ends or prints some text, a file exists, or a local port accepts connections,
/// whichever comes first, within a time limit (ADR-0027).
public struct WaitTool: ArgumentTool, JobTool {
    public struct Arguments: Decodable, Sendable {
        let job: String?
        let outputContains: String?
        let fileExists: String?
        let portOpen: Int?
        let timeoutSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case job
            case outputContains = "output_contains"
            case fileExists = "file_exists"
            case portOpen = "port_open"
            case timeoutSeconds = "timeout_seconds"
        }
    }

    public static let defaultTimeout = 60

    public let definition = ToolDefinition(
        name: "wait",
        description: """
            Wait for the first of: a job ending (job), a job printing some text (job and output_contains), a file \\
            existing (file_exists, relative to the working directory), or a local TCP port accepting connections \\
            (port_open). Returns what happened and the job's output not yet shown. timeout_seconds defaults to 60, \\
            at most 600; a timeout is not an error.
            """
    ) {
        ToolProperty.string("job").optional
        ToolProperty.string("output_contains").optional
        ToolProperty.string("file_exists").optional
        ToolProperty.integer("port_open", minimum: 1, maximum: 65_535).optional
        ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600).optional
    }

    private let access: JobAccess

    /// Waits on `jobs`, timing out on the continuous clock.
    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) }

    init(access: JobAccess) { self.access = access }

    private enum Event: Sendable {
        case jobFound, jobEnded, fileExists, portOpen, timedOut
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let job = try arguments.job.map { name throws(ToolFailure) in try access.job(name) }
        guard job != nil || arguments.fileExists != nil || arguments.portOpen != nil else {
            throw ToolFailure("Give at least one of job, file_exists or port_open.")
        }
        if arguments.outputContains != nil, job == nil { throw ToolFailure("output_contains needs a job.") }
        let seconds = Swift.min(Swift.max(1, arguments.timeoutSeconds ?? Self.defaultTimeout), 600)
        let event = await first(arguments, job: job, seconds: seconds, in: context)
        return report(event, arguments, job: job, seconds: seconds)
    }

    private func first(_ arguments: Arguments, job: Job?, seconds: Int, in context: ToolContext) async -> Event? {
        let clock = access.clock
        let needle = arguments.outputContains.map { Array($0.utf8) }
        let path = arguments.fileExists.map { $0.hasPrefix("/") ? $0 : context.workingDirectory + "/" + $0 }
        return await withTaskGroup(of: Event?.self) { group in
            if let job {
                group.addTask { await JobWaiting.watch(job, for: needle).map { $0 == .found ? .jobFound : .jobEnded } }
            }
            if let path {
                group.addTask { await FileWait.until(exists: path) ? .fileExists : nil }
            }
            if let port = arguments.portOpen {
                group.addTask { await PortWait.until(open: port, clock: clock) ? .portOpen : nil }
            }
            group.addTask { await JobWaiting.expiry(after: seconds, on: clock).map { _ in .timedOut } }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func report(_ event: Event?, _ arguments: Arguments, job: Job?, seconds: Int) -> ToolOutput {
        let headline =
            switch event {
                case .jobFound: "[\(job?.id ?? "job") printed \"\(arguments.outputContains ?? "")\"]"
                case .jobEnded: "[\(job?.id ?? "job") ended: \(job?.status.description ?? "")]"
                case .fileExists: "[\(arguments.fileExists ?? "the file") exists]"
                case .portOpen: "[port \(arguments.portOpen ?? 0) accepts connections]"
                case .timedOut: "[nothing happened within \(seconds) s]"
                case nil: "[aborted]"
            }
        guard let job else { return ToolOutput(headline) }
        if job.status != .running, event != .jobFound { return Self.ended(job, headline: headline) }
        let shown = BashTool.body(job.takeOutput())
        return ToolOutput(shown + headline + (job.status == .running ? "\n[\(job.id) still running]" : ""))
    }

    /// An ended job's result, as `bash` gives one, led by what the wait saw.
    static func ended(_ job: Job, headline: String) -> ToolOutput {
        let result = BashTool.finished(job)
        return ToolOutput(headline + "\n" + result.content, isError: result.isError)
    }
}
