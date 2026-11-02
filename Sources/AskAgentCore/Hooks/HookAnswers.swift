internal import Synchronization

/// The approvals hooks answered during one call, kept so that the loop can say them once the call is done (roadmap 0192).
final class HookAnswers: Sendable {
    private let answers = Mutex<[AgentEvent]>([])

    func record(_ event: AgentEvent) { answers.withLock { $0.append(event) } }

    /// What was recorded, emptied.
    func take() -> [AgentEvent] {
        answers.withLock { answers in
            defer { answers = [] }
            return answers
        }
    }
}
