internal import AskAgentCore
internal import AskTUI
internal import Synchronization

extension AgentConversation {
    /// After a `tasks` call, a line for each task it made done that was in progress first: what the session spent meanwhile (roadmap
    /// 0239). Said once for each time a task is done; a task made done without being started says nothing, having no span.
    func sayTaskSpend(update: @escaping @Sendable (ConversationUpdate) -> Void) {
        guard let tree = session.withLock({ $0?.tree }), let list = (try? lists.board.current()) ?? nil else { return }
        let fresh = lists.costSaid.withLock { said in
            list.tasks.filter { task in
                guard task.state == .done, let closed = task.finished ?? task.closed, said[task.id] != closed else {
                    return false
                }
                said[task.id] = closed
                return true
            }
        }
        for task in fresh {
            guard let spend = WorkSpend.of(task, in: tree), !spend.isEmpty else { continue }
            update(.notice("\(task.name) done: \(TurnSpend(spend).summary(localized: false))", isError: false))
        }
    }
}
