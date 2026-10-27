public import AskAI
public import AskAgentCore

/// `narrow_sandbox`: the model narrows the sandbox for every later call in the session (roadmap 0019, ADR-0057).
///
/// The request is the call's own `sandbox` argument, so the registry has already applied it to this call: a narrowing
/// is in `context.sandbox`, and asking for more was put to the user (or refused) before this runs. The tool stores the
/// effective policy. `reset` restores the run's own sandbox, a widening, so it asks the user itself.
public struct NarrowSandboxTool: Tool {
    public let definition = ToolDefinition(
        name: "narrow_sandbox",
        description:
            "Narrow later calls with sandbox, or restore the run policy with reset: true. Widening needs approval; stop jobs first."
    ) {
        SandboxRequest.property
        ToolProperty.boolean("reset").optional
    }

    private let jobs: JobTable

    /// Shares the run's jobs, so an existing process cannot outlive a promise to narrow every later call.
    public init(jobs: JobTable = JobTable()) { self.jobs = jobs }

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard let narrowing = context.narrowing else { return .error("This run does not keep a session sandbox.") }
        let narrows: Bool
        do { narrows = try SandboxRequest.in(input) != nil } catch { return .error("Invalid sandbox: \(error).") }
        if narrows {
            guard jobs.running.isEmpty else {
                return .error("Stop running jobs first; an existing process cannot adopt a narrower sandbox.")
            }
            let policy = context.sandbox.intersecting(context.runSandbox)
            narrowing.policy = policy
            return ToolOutput("Narrowed for the rest of the session.")
        }
        guard SandboxRequest.resets(input) else { return .error("Give a sandbox to narrow to, or reset: true.") }
        guard narrowing.policy != nil else { return ToolOutput("The session was not narrowed; nothing to reset.") }
        let question = SandboxApproval(
            tool: definition.name, input: input,
            asked: ["the run's own sandbox back, undoing the session's narrowing"], request: nil)
        guard let approve = context.approve, await approve(question) else {
            return .error("Not permitted: that request is refused.")
        }
        narrowing.policy = nil
        return ToolOutput("The session's narrowing is undone; calls run under the run's own sandbox.")
    }
}
