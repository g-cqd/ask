internal import AskAgentCore
internal import Synchronization

/// Which threads are subagents (roadmap 0063, ADR-0146), and the `agent` calls waiting for their reports.
extension ThreadTable {
    /// Marks thread `name` a subagent, running as `definition` when there is one: it merges on its own, and its summary goes to the
    /// call that started it.
    func markSubagent(_ name: String, definition: AgentDefinition? = nil) {
        state.withLock { state in
            state.subagents.insert(name)
            state.subagentDefinitions[name] = definition
        }
    }

    /// The definition subagent `name` runs as, if any.
    func subagentDefinition(_ name: String) -> AgentDefinition? { state.withLock { $0.subagentDefinitions[name] } }

    func isSubagent(_ name: String) -> Bool { state.withLock { $0.subagents.contains(name) } }

    /// The `agent` call that waits for subagent `name`'s report.
    func wait(for name: String, _ waiter: CheckedContinuation<String, Never>) {
        state.withLock { $0.waiters[name] = waiter }
    }

    /// Gives `summary` to the call waiting for subagent `name`; whether one was.
    func report(_ name: String, _ summary: String) -> Bool {
        let waiter = state.withLock { $0.waiters.removeValue(forKey: name) }
        waiter?.resume(returning: summary)
        return waiter != nil
    }

    /// Every waiting call is answered: the threads are gone (a session switch).
    func releaseWaiters() {
        let waiting = state.withLock { state in
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiting {
            waiter.resume(returning: "The subagent was stopped before it reported: the session changed.")
        }
    }
}
