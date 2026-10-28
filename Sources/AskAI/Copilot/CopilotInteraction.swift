internal import Foundation
internal import Synchronization

/// The identifier VS Code sends as `X-Interaction-Id`: one per user prompt, shared by every request the prompt's tool calls make
/// (its `InteractionService.startInteraction` runs when a chat turn begins).
final class CopilotInteraction: Sendable {
    private let current = Mutex(UUID().uuidString)

    /// The identifier for a request; a request the user started begins a new interaction.
    /// - Parameter startingNew: whether this request answers a user's prompt rather than a tool result.
    /// - Returns: the interaction's identifier.
    func id(startingNew: Bool) -> String {
        current.withLock { value in
            if startingNew { value = UUID().uuidString }
            return value
        }
    }
}
