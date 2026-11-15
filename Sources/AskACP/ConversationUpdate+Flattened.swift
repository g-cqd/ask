internal import AskTUI

extension ConversationUpdate {
    /// The update, or the updates a ``batch`` holds, in order and however deep.
    var flattened: [ConversationUpdate] {
        guard case .batch(let updates) = self else { return [self] }
        return updates.flatMap(\.flattened)
    }
}
