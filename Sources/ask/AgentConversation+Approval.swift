internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// A tool call that asks for more than the sandbox allows is put to the user (roadmap 0019, ADR-0055).
extension AgentConversation {
    /// The approval state: questions waiting for an answer, what the user allowed for the session, and where the
    /// current run's questions go.
    struct Approvals {
        var nextID = 0
        var waiting: [Int: (request: SandboxRequest, answer: CheckedContinuation<Bool, Never>)] = [:]
        /// Requests the user allowed for the session; a later request they contain is not asked again.
        var grants: [SandboxRequest] = []
        var ask: (@Sendable (ConversationUpdate) -> Void)?
    }

    /// Asks the user about `approval`, unless a grant for the session covers it. Cancelling the run answers no.
    func approve(_ approval: SandboxApproval) async -> Bool {
        let grants = approvals.withLock { $0.grants }
        if approval.request.isCovered(by: grants, workingDirectory: source.workspace) { return true }
        let question =
            "\(approval.tool) \(toolSummary(name: approval.tool, input: approval.input)) asks for "
            + approval.asked.joined(separator: " and ") + ". Allow it?"
        let id = approvals.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
                let ask = approvals.withLock { state in
                    state.waiting[id] = (approval.request, answer)
                    return state.ask
                }
                // Cancelled before the question was stored: the handler found nothing to answer, so answer here.
                if Task.isCancelled { resolve(id, allowed: false) }
                guard let ask else { return resolve(id, allowed: false) }
                ask(.askApproval(id: id, question: question))
            }
        } onCancel: {
            resolve(id, allowed: false)
        }
    }

    func answer(approval id: Int, with choice: ApprovalChoice) {
        if choice == .session {
            approvals.withLock { state in
                if let request = state.waiting[id]?.request { state.grants.append(request) }
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
