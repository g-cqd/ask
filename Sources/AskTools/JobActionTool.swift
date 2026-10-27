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
        description:
            "Send input (default), inspect status, stop, or wait. wait ends on output/port/file readiness or job completion. "
            + "timeout_seconds: input default 1, wait default 60, max 600. A wait timeout/cancel leaves the job running."
    ) {
        ToolProperty.string("job")
        // @dl:accept -- independent tools declare wire fields through the same builder; their field lists are data
        ToolProperty.schema("action", #"{"type":"string","enum":["input","status","stop","wait"]}"#).optional
        ToolProperty.string("text").optional
        ToolProperty.boolean("close_input").optional
        ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600).optional
        ToolProperty.string("wait_for_output", minLength: 1).optional
        ToolProperty.integer("wait_for_port", minimum: 1, maximum: 65_535).optional
        // @dl:accept -- tool declarations share schema/storage/initializer syntax, not a second implementation
        ToolProperty.string("wait_for_file", minLength: 1).optional
    }

    private let access: JobAccess

    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) }
    init(access: JobAccess) { self.access = access }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let action = arguments.action ?? .input
        let requested = arguments.waitForOutput != nil || arguments.waitForPort != nil || arguments.waitForFile != nil
        if action == .stop || action == .status {
            guard !requested else { throw ToolFailure("Readiness parameters require action input or wait.") }
        }
        if action == .wait, arguments.text != nil || arguments.closeInput == true {
            throw ToolFailure("Use action input to send text or close standard input.")
        }
        let readiness = try ShellReadiness.select(
            output: arguments.waitForOutput, port: arguments.waitForPort,
            file: arguments.waitForFile, in: context)
        let job = try access.job(arguments.job)
        switch action {
            case .status:
                return ToolOutput(BashTool.body(job.takeOutput()) + "[\(job.id) status: \(job.status.description)]")
            case .stop:
                return try await JobStopTool(jobs: access.jobs).run(.init(job: arguments.job), in: context)
            case .input, .wait:
                if action == .input { try job.sendInput(arguments.text, closing: arguments.closeInput == true) }
                let seconds = Swift.min(Swift.max(1, arguments.timeoutSeconds ?? (action == .wait ? 60 : 1)), 600)
                let outcome = try await JobWaiting.wait(
                    for: job, readiness: readiness, seconds: seconds,
                    clock: access.clock, in: context)
                if job.status != .running { return WaitTool.ended(job, headline: "[\(job.id) ended]") }
                let headline =
                    switch outcome {
                        case .found: "[\(job.id) \(readiness?.headline ?? "ready")]"
                        case .cancelled: "[aborted; \(job.id) still running]"
                        case .timedOut where action == .wait:
                            "[nothing happened within \(seconds) s; \(job.id) still running]"
                        default: "[\(job.id) still running]"
                    }
                return ToolOutput(BashTool.body(job.takeOutput()) + headline, isError: outcome == .cancelled)
        }
    }
}
