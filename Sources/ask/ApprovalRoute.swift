internal import AskTUI

/// Where a question asked inside a run goes, when it is not the main run's (roadmap 0195): a thread's run sets its own, so its approvals
/// and the model's questions reach its lane, and are not declined when main's turn ends. Task-local, so every tool and hook of the run
/// asks through it, however deep in the run's tasks it asks.
struct ApprovalRoute: Sendable {
    @TaskLocal static var current: ApprovalRoute?

    /// Sends what the screen shows for a question.
    let send: @Sendable (ConversationUpdate) -> Void
    /// Says a question begins (true) or is settled (false), so the runner shows it is waiting on the person.
    let waiting: @Sendable (Bool) -> Void
}
