public import AskAI
public import AskAgentCore

/// Controls background jobs by canonical ID or collision-safe alias. Waiting never owns their lifetime.
public struct JobActionTool: ArgumentTool, JobTool {
    public enum Action: String, Decodable, Sendable {
        case input, stop, status, wait
    }

    public struct Arguments: Decodable, Sendable {
        let job: String
        let action: Action?
        let text: String?
        let closeInput: Bool?
        let timeoutSeconds: Int?
        /// Not arguments of this tool (ADR-0159): read only to say where they go, since a wait that ignored one would sit
        /// out its whole time for something it was never watching.
        let waitForOutput: String?
        let waitForPort: Int?
        let waitForFile: String?

        enum CodingKeys: String, CodingKey {
            case job, action, text
            case closeInput = "close_input"
            case timeoutSeconds = "timeout_seconds"
            case waitForOutput = "wait_for_output"
            case waitForPort = "wait_for_port"
            case waitForFile = "wait_for_file"
        }
    }

    public let definition = ToolDefinition(
        name: "job",
        description: """
            Act on a command bash left running as a job: write to it, read its status and what it printed since, wait for it \
            to end, or stop it.
            Each returns what the job printed since it was last shown. A wait whose time is up leaves the job running. To \
            wait for a text, a port or a file, start the command with bash's wait_for. Stop the jobs you started once they \
            are no longer needed.
            """
    ) {
        ToolProperty.string("job").described("The job's name, as bash gave it: job-1.")
        // @dl:accept -- independent tools declare wire fields through the same builder; their field lists are data
        ToolProperty.schema("action", #"{"type":"string","enum":["input","status","stop","wait"]}"#)
            .described("What to do: input unless given.").optional
        ToolProperty.string("text").described("With input: what to write to the job's standard input.").optional
        ToolProperty.boolean("close_input").described("With input: close the job's standard input after writing.")
            .optional
        ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600)
            .described("How long to wait for the job to end: 1 with input, 60 with wait, unless given.")
            .optional
    }

    private let access: JobAccess

    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) }
    init(access: JobAccess) { self.access = access }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let action = arguments.action ?? .input
        guard arguments.waitForOutput == nil, arguments.waitForPort == nil, arguments.waitForFile == nil else {
            throw ToolFailure(
                "job waits only for the job to end: give timeout_seconds and read what it printed. "
                    + "A text, a port or a file is waited for by bash's wait_for, when the command starts."
            )
        }
        if action == .wait, arguments.text != nil || arguments.closeInput == true {
            throw ToolFailure("Use action input to send text or close standard input.")
        }
        let job = try access.job(arguments.job)
        switch action {
            case .status:
                return ToolOutput(BashTool.body(job.takeOutput()) + "[\(job.id) status: \(job.status.description)]")
            case .stop:
                let wasRunning = job.status == .running
                job.stop()
                await job.ended()
                let headline = wasRunning ? "[\(job.id) stopped]" : "[\(job.id) had already ended]"
                let result = JobWaiting.ended(job, headline: headline)
                // A stop that was asked for and happened is the tool succeeding, not the command failing.
                return wasRunning && job.status == .stopped ? ToolOutput(result.content) : result
            case .input, .wait:
                if action == .input { try job.sendInput(arguments.text, closing: arguments.closeInput == true) }
                let seconds = Swift.min(Swift.max(1, arguments.timeoutSeconds ?? (action == .wait ? 60 : 1)), 600)
                // The end only (ADR-0159): a text, a port or a file is waited for where the command starts, by bash.
                let outcome = await JobWaiting.wait(for: job, needle: nil, seconds: seconds, clock: access.clock)
                if job.status != .running { return JobWaiting.ended(job, headline: "[\(job.id) ended]") }
                let headline =
                    switch outcome {
                        case .cancelled: "[aborted; \(job.id) still running]"
                        case .timedOut where action == .wait:
                            "[nothing happened within \(seconds) s; \(job.id) still running]"
                        default: "[\(job.id) still running]"
                    }
                return ToolOutput(BashTool.body(job.takeOutput()) + headline, isError: outcome == .cancelled)
        }
    }
}
