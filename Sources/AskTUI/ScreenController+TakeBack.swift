/// Option+Up takes the newest queued message back into the input, unsent, to edit (roadmap 0174). The agent has a copy of it, so it is
/// asked to let it go; a message it has already taken into the conversation stays sent. Queued again, it goes last.
extension ScreenController {
    /// What Option+Up does: nil when it takes nothing back, so the key goes on to the editor.
    mutating func takeBackQueued() -> [Effect]? {
        guard let prompt = pending.last else { return nil }
        guard state.editor.text.isEmpty else {
            state.detail = "Clear the input to edit the queued message."
            return []
        }
        guard withdrawing == nil else { return [] }
        // While the input is returned after a stop, the queue is the screen's alone.
        if returningInput {
            promptWithdrawn(id: prompt.id, withdrawn: true)
            return []
        }
        withdrawing = prompt.id
        return [.withdrawPrompt(id: prompt.id)]
    }

    mutating func promptWithdrawn(id: Int, withdrawn: Bool) {
        if withdrawing == id { withdrawing = nil }
        guard pending.contains(where: { $0.id == id }) else { return }
        guard withdrawn else {
            state.detail = "That message was already sent."
            return
        }
        returnToInput(id: id, leaving: .notice("Taken back to edit.", isError: false))
    }
}
