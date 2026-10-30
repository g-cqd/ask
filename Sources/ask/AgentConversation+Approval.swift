internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// A tool call that asks for more than the sandbox allows is put to the user (roadmap 0019, ADR-0055).
extension AgentConversation {
    /// The approval state: questions waiting for an answer, what the user allowed for the session, and where the
    /// current run's questions go.
    struct Approvals {
        var nextID = 0
        var waiting:
            [Int: (request: SandboxRequest?, destructiveKey: String?, answer: CheckedContinuation<Bool, Never>)] = [:]
        /// What each waiting call question would remember for the session (roadmap 0134).
        var callScopes: [Int: CallScope] = [:]
        /// What the person allowed for the session: subcommands, programs, files, other tools.
        var calls = CallGrants()
        /// Requests the user allowed for the session; a later request they contain is not asked again.
        var grants: [SandboxRequest] = []
        /// Server tools the user allowed for the session, as `server/tool` (ADR-0111).
        var destructiveGrants: Set<String> = []
        var ask: (@Sendable (ConversationUpdate) -> Void)?
        /// The model's questions waiting for the person (roadmap 0117).
        var questions: [Int: CheckedContinuation<[PersonAnswer]?, Never>] = [:]
    }

    /// Asks the user about `approval`, unless a grant for the session covers it. Cancelling the run answers no.
    func approve(_ approval: SandboxApproval) async -> Bool {
        let grants = approvals.withLock { $0.grants }
        if let request = approval.request, request.isCovered(by: grants, workingDirectory: source.workspace) {
            return true
        }
        // The command is shown whole under the question, folded (roadmap 0157), so the question does not repeat it.
        let question = "\(approval.tool) asks for " + approval.asked.joined(separator: " and ") + ". Allow it?"
        // Nothing to remember (a reset of the session's narrowing) is a yes or no.
        return await ask(
            // @dl:accept -- each kind of question ends by asking with its own grant to remember
            question, remembering: (approval.request, nil), kind: approval.request == nil ? .confirm : .grant,
            detail: ToolSummary.fullInput(for: approval.input))
        // @dl:accept -- the approvers sit side by side, each with its own question and grant; their shape is the protocol
    }

    /// Asks the user about a server's tool that the server marks destructive (ADR-0111), unless they allowed it for the session.
    func approveDestructive(_ call: DestructiveToolCall) async -> Bool {
        // @dl:accept -- each kind of question checks its own grants and says its own sentence
        if approvals.withLock({ $0.destructiveGrants.contains(call.grantKey) }) { return true }
        let question =
            "The MCP server \(call.server)'s tool \(call.tool) may change or destroy things: the server does not say it is read-only. "
            + "Allow it?"
        return await ask(
            question, remembering: (nil, call.grantKey), kind: .destructive,
            detail: String(decoding: call.input.bytes, as: UTF8.self))
    }

    /// What the loop for `settings` consults before a call that changes things (roadmap 0134).
    func callGate(for settings: RunSettings) -> ToolCallGate {
        ToolCallGate(policy: settings.approvalPolicy) { [weak self] in await self?.approveCall($0) ?? false }
    }

    /// Asks the person about a call that changes things (roadmap 0134), unless a grant for the session covers it.
    func approveCall(_ approval: ToolCallApproval) async -> Bool {
        if approvals.withLock({ $0.calls.covers(approval.scope) }) { return true }
        // A command is shown whole under the question; a file or a job is named in it.
        let isCommand: Bool = if case .command = approval.scope { true } else { false }
        let question =
            isCommand
            ? "\(approval.tool) wants to run this. Allow it?"
            : "\(approval.tool) \(ToolSummary.line(for: approval.input)). Allow it?"
        let kind: ApprovalKind =
            switch approval.scope {
                case .command(let words) where words.coverable:
                    .command(phrases: words.phrases, programs: words.programs)
                case .command: .command(phrases: [], programs: [])
                case .file, .tool: .grant
            }
        return await ask(
            question, remembering: (nil, nil), kind: kind, scope: approval.scope,
            detail: isCommand ? ToolSummary.fullInput(for: approval.input) : nil)
    }

    /// Puts `question` to the user and waits; false when the run is cancelled or there is no one to ask. What a session grant
    /// remembers is `remembering`, for the answer's `a`.
    private func ask(
        _ question: String, remembering: (request: SandboxRequest?, destructiveKey: String?), kind: ApprovalKind,
        scope: CallScope? = nil, detail: String? = nil
    ) async -> Bool {
        let id = approvals.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
                let ask = approvals.withLock { state in
                    state.waiting[id] = (remembering.request, remembering.destructiveKey, answer)
                    if let scope { state.callScopes[id] = scope }
                    return state.ask
                }
                // Cancelled before the question was stored: the handler found nothing to answer, so answer here.
                if Task.isCancelled { resolve(id, allowed: false) }
                guard let ask else { return resolve(id, allowed: false) }
                ask(.askApproval(id: id, question: question, kind: kind, detail: detail))
            }
        } onCancel: {
            resolve(id, allowed: false)
        }
    }

    func answer(approval id: Int, with choice: ApprovalChoice) {
        approvals.withLock { state in
            let scope = state.callScopes.removeValue(forKey: id)
            if choice == .session {
                if let request = state.waiting[id]?.request { state.grants.append(request) }
                if let key = state.waiting[id]?.destructiveKey { state.destructiveGrants.insert(key) }
                if let scope { state.calls.grant(scope) }
            }
            if choice == .program, case .command(let words)? = scope { state.calls.grantPrograms(words) }
        }
        resolve(id, allowed: choice != .deny)
    }

    /// Answers question `id` once; a second answer, or one to a question already answered, does nothing.
    private func resolve(_ id: Int, allowed: Bool) {
        let waiting = approvals.withLock { $0.waiting.removeValue(forKey: id) }
        waiting?.answer.resume(returning: allowed)
    }
}
