internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// Sends `/loop`'s prompts when they are due (roadmap 0228): one task sleeps until the next is due, then sends it as the person's next
/// message, or skips it while a turn runs; it is started again whenever the schedule changes. Loops live as long as ask is open.
final class RecurringDriver: Sendable {
    private let origin = ContinuousClock.now
    private let state = Mutex<(schedule: RecurringPrompts, task: Task<Void, Never>?)>((RecurringPrompts(), nil))

    var now: Duration { ContinuousClock.now - origin }
    var schedule: RecurringPrompts { state.withLock { $0.schedule } }

    /// Changes the schedule with `change`, then plans the next wake.
    func change<Result>(
        _ change: (inout RecurringPrompts) -> Result,
        turnRunning: @escaping @Sendable () -> Bool,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Result {
        let result = state.withLock { change(&$0.schedule) }
        plan(turnRunning: turnRunning, update: update)
        return result
    }

    private func plan(
        turnRunning: @escaping @Sendable () -> Bool,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) {
        let next = state.withLock { state in
            state.task?.cancel()
            state.task = nil
            return state.schedule.nextDue
        }
        guard let next else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: max(.zero, next - self.now))
            guard !Task.isCancelled else { return }
            let ticks = self.state.withLock { $0.schedule.tick(now: self.now, turnRunning: turnRunning()) }
            for tick in ticks { Self.show(tick, update: update) }
            self.plan(turnRunning: turnRunning, update: update)
        }
        state.withLock { $0.task = task }
    }

    private static func show(_ tick: RecurringPrompts.Tick, update: @Sendable (ConversationUpdate) -> Void) {
        switch tick {
            case .send(let id, let prompt, let run): update(.submitPrompt("[loop \(id), run \(run)] \(prompt)"))
            case .skipped(let id): update(.notice("Loop \(id) skipped: a turn was running.", isError: false))
            case .finished(let id, let runs): update(.notice("Loop \(id) ended after \(runs) runs.", isError: false))
        }
    }
}
