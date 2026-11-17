internal import AskAI

/// A call's own `sandbox` argument (ADR-0054), and what it asks of the session's (ADR-0162).
extension ToolRegistry {
    /// Where a built-in call goes next: into a context, with what to say of the session's sandbox, or back to the model refused.
    enum Applied {
        case run(ToolContext, said: String?)
        case refused(ToolOutput)
    }

    private static let notPermitted = ToolOutput.error("Not permitted: that request is refused.")

    /// The context a built-in tool runs in once the call's own `sandbox` request, if it made one, is applied; or the refusal.
    /// - Parameters:
    ///   - name: the tool called, for the question and the refusal.
    ///   - input: the call's arguments.
    ///   - narrowed: the context under the session's narrowing, which the request applies to.
    ///   - unnarrowed: the context under the run's own sandbox, which a reset the person allows gives back.
    /// - Returns: the context to run in, or the refusal.
    func applyingRequest(
        of name: String,
        input: JSONObject,
        to narrowed: ToolContext,
        unnarrowed: ToolContext
    ) async -> Applied {
        let request: SandboxRequest
        do {
            guard let given = try SandboxRequest.in(input) else { return .run(narrowed, said: nil) }
            request = given
        } catch {
            return .refused(.error("Invalid sandbox for \(name): \(error)."))
        }
        var context = narrowed
        var said: String?
        switch request.session {
            case nil: break
            case .keep:
                if let refusal = keepRefusal(request, in: context) { return .refused(.error(refusal)) }
            case .reset:
                guard let narrowing = context.narrowing, narrowing.policy != nil else {
                    said = "The session was not narrowed; nothing to reset."
                    break
                }
                // A widening, and an operation rather than a capability: no remembered grant covers it (ADR-0057).
                let question = SandboxApproval(
                    tool: name,
                    input: input,
                    asked: ["the run's own sandbox back, undoing the session's narrowing"],
                    request: nil
                )
                guard let approve = context.approve, await approve(question) else { return .refused(Self.notPermitted) }
                narrowing.policy = nil
                context = unnarrowed
                said = "The session's narrowing is undone."
        }
        let policy: SandboxPolicy
        switch request.applied(to: context.sandbox, workingDirectory: context.workingDirectory) {
            case .narrowed(let within): policy = within
            case .refused(let asked):
                // Only the user widens: an approver asks them; without one the call is refused.
                let question = SandboxApproval(tool: name, input: input, asked: asked, request: request.forOneCall)
                guard let approve = context.approve, await approve(question) else { return .refused(Self.notPermitted) }
                policy = request.granted(over: context.sandbox, workingDirectory: context.workingDirectory)
            case .invalid(let reason): return .refused(.error("Invalid sandbox for \(name): \(reason)."))
        }
        if request.session == .keep {
            // Never past the run: what the person granted this call is not the session's to keep beyond the run's ceiling.
            context.narrowing?.policy = policy.intersecting(context.runSandbox)
            said = "Narrowed for the rest of the session."
        }
        return .run(context.with(policy), said: said)
    }

    /// Why this call cannot narrow the session, or nil when it can.
    private func keepRefusal(_ request: SandboxRequest, in context: ToolContext) -> String? {
        if context.narrowing == nil { return "This run does not keep a session sandbox." }
        if request.forOneCall == SandboxRequest() {
            return "Invalid sandbox: session: keep needs a network, write or read to keep."
        }
        if busy() { return "Stop running jobs first; an existing process cannot adopt a narrower sandbox." }
        return nil
    }
}
