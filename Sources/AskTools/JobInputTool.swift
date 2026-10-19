public import AskAI
public import AskAgentCore

/// `job_input`: writes to a job's standard input, then returns the output that follows (ADR-0027).
public struct JobInputTool: ArgumentTool, JobTool {
    public struct Arguments: Decodable, Sendable {
        let job: String
        let text: String?
        let closeInput: Bool?
        let yieldSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case job, text
            case closeInput = "close_input"
            case yieldSeconds = "yield_seconds"
        }
    }

    public let definition = ToolDefinition(
        name: "job_input",
        description: """
            Write text to a job's standard input (include the newline a program expects), optionally close it so \\
            the program sees end-of-file, then wait yield_seconds (default 1, at most 60) or until the job ends, \\
            and return its output not yet shown.
            """
    ) {
        ToolProperty.string("job")
        ToolProperty.string("text").optional
        // @dl:accept -- every job tool ends its schema, holds its JobAccess and has the same two one-line initialisers; that is the tool's shape, not logic to share
        ToolProperty.boolean("close_input").optional
        ToolProperty.integer("yield_seconds", minimum: 1, maximum: 60).optional
    }

    private let access: JobAccess

    /// Writes to jobs in `jobs`, waiting on the continuous clock.
    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) }

    init(access: JobAccess) { self.access = access }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let job = try access.job(arguments.job)
        if let text = arguments.text, !job.write(Array(text.utf8)) {
            throw ToolFailure(
                "\(job.id) does not take input: \(job.status == .running ? "input is closed" : "it ended").")
        }
        if arguments.closeInput == true { job.closeInput() }
        let seconds = Swift.min(Swift.max(1, arguments.yieldSeconds ?? 1), 60)
        _ = await JobWaiting.wait(for: job, needle: nil, seconds: seconds, clock: access.clock)
        if job.status != .running { return WaitTool.ended(job, headline: "[\(job.id) ended]") }
        return ToolOutput(BashTool.body(job.takeOutput()) + "[\(job.id) still running]")
    }
}
