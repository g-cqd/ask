internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// `/loop` (roadmap 0228): prompts sent on a schedule, in the main conversation.
extension AgentConversation {
    func loopCommand(_ arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        let running: @Sendable () -> Bool = { [weak self] in self?.current.withLock { $0.turnRunning } ?? false }
        switch RecurringCommand.parse(arguments) {
            case .list: update(.notice(Self.describe(recurring.schedule, now: recurring.now), isError: false))
            case .add(let every, let prompt):
                let id = recurring.change(
                    { $0.add(every: every, prompt: prompt, now: recurring.now) },
                    turnRunning: running,
                    update: update
                )
                update(
                    .notice(
                        "Loop \(id): every \(RecurringCommand.describe(every)), \(prompt)\nAt most \(RecurringPrompts.maximumRuns) runs, "
                            + "for 7 days at most, while ask is open; skipped while a turn runs. /loop stop \(id) ends it.",
                        isError: false
                    )
                )
            case .stop(let id):
                let removed = recurring.change({ $0.remove(id) }, turnRunning: running, update: update)
                update(.notice(removed ? "Loop \(id) stopped." : "There is no loop \(id).", isError: !removed))
            case .stopAll:
                recurring.change({ $0.removeAll() }, turnRunning: running, update: update)
                update(.notice("Every loop stopped.", isError: false))
            case .invalid(let message): update(.notice(message, isError: true))
        }
    }

    static func describe(_ schedule: RecurringPrompts, now: Duration) -> String {
        guard !schedule.entries.isEmpty else { return "No loops. " + RecurringCommand.usage }
        return schedule.entries
            .map { entry in
                let minutes = max(0, Int((entry.next - now).components.seconds / 60))
                return
                    "\(entry.id). every \(RecurringCommand.describe(entry.every)): \(entry.prompt) (\(entry.runs) runs, "
                    + "\(entry.skipped) skipped; next in \(minutes) min)"
            }
            .joined(separator: "\n")
    }
}
