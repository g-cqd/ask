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
        description: """
            Narrow the sandbox for every later call in this session, with the same fields as a call's sandbox argument. \
            Stop running jobs first. Asking for more than now, or reset: true to restore the run's own sandbox, \
            needs the user's approval. Later calls stay bounded by the run's policy even after approval.
            """
    ) {
        SandboxRequest.property
        ToolProperty.boolean("reset").optional
    }

    private let jobs: JobTable

    /// Shares the run's jobs, so an existing process cannot outlive a promise to narrow every later call.
    public init(jobs: JobTable = JobTable()) { self.jobs = jobs }

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard let narrowing = context.narrowing else { return .error("This run does not keep a session sandbox.") }
        let request: SandboxRequest?
        do { request = try SandboxRequest.in(input) } catch { return .error("Invalid sandbox: \(error).") }
        if let request {
            guard jobs.running.isEmpty else {
                return .error("Stop running jobs first; an existing process cannot adopt a narrower sandbox.")
            }
            let policy = context.sandbox.intersecting(context.runSandbox)
            narrowing.policy = policy
            return ToolOutput("From now on every call runs under: \(Self.describe(policy, request))")
        }
        guard SandboxRequest.resets(input) else { return .error("Give a sandbox to narrow to, or reset: true.") }
        guard narrowing.policy != nil else { return ToolOutput("The session was not narrowed; nothing to reset.") }
        let question = SandboxApproval(
            tool: definition.name, input: input,
            asked: ["the run's own sandbox back, undoing the session's narrowing"], request: nil)
        guard let approve = context.approve, await approve(question) else {
            return .error("Only the user can widen the sandbox; the session stays narrowed.")
        }
        narrowing.policy = nil
        return ToolOutput("The session's narrowing is undone; calls run under the run's own sandbox.")
    }

    /// What was narrowed, in words: the dimensions the request named, at their effective values.
    private static func describe(_ policy: SandboxPolicy, _ request: SandboxRequest) -> String {
        func scope(_ scope: PathScope) -> String {
            guard case .roots(let roots) = scope else { return "anywhere" }
            return roots.isEmpty ? "temporary directories only" : roots.joined(separator: ", ")
        }
        var parts: [String] = []
        if request.network != nil { parts.append("network \(policy.network)") }
        if request.write != nil { parts.append("writes under \(scope(policy.write))") }
        if request.read != nil { parts.append("reads under \(scope(policy.read))") }
        return parts.isEmpty ? "the same sandbox as before." : parts.joined(separator: "; ") + "."
    }
}
