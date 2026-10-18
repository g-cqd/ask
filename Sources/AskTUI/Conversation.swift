internal import TerminalKitCodecs
internal import TerminalKitInput

/// Starts runs for the screen. Implemented by the composition root over the agent loop, so AskTUI never
/// imports the agent (ADR-0009).
public protocol Conversation: Sendable {
    /// Starts a run for `prompt`. Updates arrive through `update`, ending with ``ConversationUpdate/runEnded``.
    /// - Returns: the run's task; cancelling it aborts the run.
    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>
}
