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
        /// Requests the user allowed for the session; a later request they contain is not asked again.
        var grants: [SandboxRequest] = []
        /// Server tools the user allowed for the session, as `server/tool` (ADR-0111).
        var destructiveGrants: Set<String> = []
        var ask: (@Sendable (ConversationUpdate) -> Void)?
    }

    /// Asks the user about `approval`, unless a grant for the session covers it. Cancelling the run answers no.
    func approve(_ approval: SandboxApproval) async -> Bool {
        let grants = approvals.withLock { $0.grants }
        if let request = approval.request, request.isCovered(by: grants, workingDirectory: source.workspace) {
            return true
        }
        let question =
            "\(approval.tool) \(ToolSummary.line(for: approval.input)) asks for "
            + approval.asked.joined(separator: " and ") + ". Allow it?"
        // Nothing to remember (a reset of the session's narrowing) is a yes or no.
        return await ask(
            question, remembering: (approval.request, nil), kind: approval.request == nil ? .confirm : .grant)
    }

    /// Asks the user about a server's tool that the server marks destructive (ADR-0111), unless they allowed it for the session.
    func approveDestructive(_ call: DestructiveToolCall) async -> Bool {
        if approvals.withLock({ $0.destructiveGrants.contains(call.grantKey) }) { return true }
        let question =
            "The MCP server \(call.server)'s tool \(call.tool) (\(ToolSummary.line(for: call.input))) "
            + "is marked destructive: it may destroy or overwrite. Allow it?"
        return await ask(question, remembering: (nil, call.grantKey), kind: .destructive)
    }

    /// Puts `question` to the user and waits; false when the run is cancelled or there is no one to ask. What a session grant
    /// remembers is `remembering`, for the answer's `a`.
    private func ask(
        _ question: String, remembering: (request: SandboxRequest?, destructiveKey: String?), kind: ApprovalKind
    ) async -> Bool {
        let id = approvals.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
                let ask = approvals.withLock { state in
                    state.waiting[id] = (remembering.request, remembering.destructiveKey, answer)
                    return state.ask
                }
                // Cancelled before the question was stored: the handler found nothing to answer, so answer here.
                if Task.isCancelled { resolve(id, allowed: false) }
                guard let ask else { return resolve(id, allowed: false) }
                ask(.askApproval(id: id, question: question, kind: kind))
            }
        } onCancel: {
            resolve(id, allowed: false)
        }
    }

    func answer(approval id: Int, with choice: ApprovalChoice) {
        if choice == .session {
            approvals.withLock { state in
                if let request = state.waiting[id]?.request { state.grants.append(request) }
                if let key = state.waiting[id]?.destructiveKey { state.destructiveGrants.insert(key) }
            }
        }
        resolve(id, allowed: choice != .deny)
    }

    /// Answers question `id` once; a second answer, or one to a question already answered, does nothing.
    private func resolve(_ id: Int, allowed: Bool) {
        let waiting = approvals.withLock { $0.waiting.removeValue(forKey: id) }
        waiting?.answer.resume(returning: allowed)
    }
}
