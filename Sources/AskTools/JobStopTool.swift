public import AskAI
public import AskAgentCore

/// `job_stop`: stops a job and every process it started, and returns its last output (ADR-0027).
public struct JobStopTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let job: String
    }

    public let definition = ToolDefinition(
        name: "job_stop",
        description: """
            Stop a job and every process it started (SIGTERM, then SIGKILL after 2 s), and return its output not \\
            yet shown.
            """
    ) {
        ToolProperty.string("job")
    }

    private let access: JobAccess

    /// Stops jobs in `jobs`.
    public init(jobs: JobTable) { access = JobAccess(jobs: jobs, clock: ContinuousClock()) }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let job = try access.job(arguments.job)
        let wasRunning = job.status == .running
        job.stop()
        await job.ended()
        let result = WaitTool.ended(job, headline: wasRunning ? "[\(job.id) stopped]" : "[\(job.id) had already ended]")
        // A stop that was asked for and happened is the tool succeeding, not the command failing.
        return wasRunning && job.status == .stopped ? ToolOutput(result.content) : result
    }
}
