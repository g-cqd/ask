extension ScreenController {
    /// Kept by the screen until the agent acknowledges persistence, not merely delivery to its task.
    struct Pending: Sendable {
        let id: Int
        let text: String
        let followUp: Bool

        var effect: Effect { .queuePrompt(id: id, text: text, followUp: followUp) }
    }

    mutating func submitPrompt(_ text: String, followUp: Bool) -> [Effect] {
        guard text.contains(where: { !$0.isWhitespace }) else {
            state.transcript.addNotice("Give a message after /follow-up.", isError: true)
            return []
        }
        if state.running { return queue(text, followUp: followUp) }
        state.transcript.addUser(text)
        return begin(.startRun(text))
    }

    mutating func queue(_ text: String, followUp: Bool) -> [Effect] {
        guard acceptsInput else {
            state.editor.restore(text)
            state.transcript.addNotice("A command is running; the prompt stays in the editor.", isError: false)
            return []
        }
        let prompt = Pending(id: nextPromptID, text: text, followUp: followUp)
        nextPromptID += 1
        pending.append(prompt)
        let kind = followUp ? "follow-up" : "steering"
        state.transcript.addNotice("Queued \(kind): \(text)", isError: false)
        // During abort, keep input locally: the cancelled run must not consume it.
        return returningInput ? [] : [prompt.effect]
    }

    mutating func endRun() -> [Effect] {
        state.running = false
        acceptsInput = false
        if returningInput {
            let texts = pending.map(\.text) + (state.editor.text.isEmpty ? [] : [state.editor.text])
            state.editor.restore(texts.joined(separator: "\n\n"))
            pending.removeAll()
            returningInput = false
            return []
        }
        guard !pending.isEmpty, state.exitRequest == nil else { return [] }
        // A message may arrive after the agent's last boundary but before runEnded reaches the screen.
        // It is still ours until acknowledged, so start it now and reoffer the others to the new run.
        let index = pending.firstIndex(where: { !$0.followUp }) ?? pending.startIndex
        let first = pending.remove(at: index)
        state.transcript.addUser(first.text)
        return begin(.startRun(first.text)) + pending.map(\.effect)
    }

    /// Puts `text` in the editor if the person has written nothing there; otherwise keeps their draft and shows the text in a notice.
    mutating func fill(draft text: String) {
        guard state.editor.text.allSatisfy(\.isWhitespace) else {
            state.transcript.addNotice("Your draft was kept. The prompt you went back to was:\n\(text)", isError: false)
            return
        }
        state.editor.restore(text)
    }
}
