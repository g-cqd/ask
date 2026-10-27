internal import AskAgentCore

extension JobWaiting {
    /// Optional readiness augments completion waits without changing process ownership or consuming output.
    static func wait(
        for job: Job, readiness: ShellReadiness?, seconds: Int, clock: any Clock<Duration>, in context: ToolContext
    )
        async throws(ToolFailure) -> Outcome
    {
        if let readiness { return try await readiness.wait(for: job, seconds: seconds, clock: clock, in: context) }
        return await wait(for: job, needle: nil, seconds: seconds, clock: clock)
    }
}
