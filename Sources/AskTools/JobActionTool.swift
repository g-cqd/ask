public import AskAI
public import AskAgentCore

/// Controls background jobs by canonical ID or their collision-safe display alias.
public struct JobActionTool: ArgumentTool, JobTool {
    public enum Action: String, Decodable, Sendable {
        case input, stop, status
    }

    public struct Arguments: Decodable, Sendable {
        let job: String
        let action: Action?
        let text: String?
        let closeInput: Bool?
        let timeoutSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case job, action, text
            // @dl:accept -- wire-key mappings have the same syntax, but job actions and file edits are distinct contracts
            case closeInput = "close_input"
            case timeoutSeconds = "timeout_seconds"
        }
    }

    public let definition = ToolDefinition(
        name: "job",
        description: "Send input, inspect status, or stop a background job. action: input (default), status, stop."
    ) {
        ToolProperty.string("job")
        ToolProperty.string("action").optional
        ToolProperty.string("text").optional
        // @dl:accept -- shared input schema fields intentionally mirror the legacy tool that implements this action
        ToolProperty.boolean("close_input").optional
        // @dl:accept -- job tools share the same access storage and initializer shape, not additional logic
        ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 60).optional
    }

    private let access: JobAccess

    public init(jobs: JobTable) { self.init(jobs: jobs, clock: ContinuousClock()) }

    init(access: JobAccess) { self.access = access }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        switch arguments.action ?? .input {
            case .status:
                let job = try access.job(arguments.job)
                return ToolOutput(BashTool.body(job.takeOutput()) + "[\(job.id) status: \(job.status.description)]")
            case .stop:
                return try await JobStopTool(jobs: access.jobs).run(.init(job: arguments.job), in: context)
            case .input:
                return try await JobInputTool(access: access)
                    .run(
                        .init(
                            job: arguments.job, text: arguments.text, closeInput: arguments.closeInput,
                            yieldSeconds: arguments.timeoutSeconds), in: context)
        }
    }
}
