extension ScreenController {
    /// Kept by the screen until the agent acknowledges persistence, not merely delivery to its task.
    struct Pending: Sendable {
        let id: Int
        let text: String
        let followUp: Bool
        let transcriptIndex: Int

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
        state.transcript.addQueued(text)
        let index = state.transcript.items.count - 1
        let prompt = Pending(id: nextPromptID, text: text, followUp: followUp, transcriptIndex: index)
        nextPromptID += 1
        pending.append(prompt)
        // During abort, keep input locally: the cancelled run must not consume it.
        return returningInput ? [] : [prompt.effect]
    }

    mutating func endRun() -> [Effect] {
        state.running = false
        state.abortArmedAt = nil
        state.abortArmedAction = nil
        acceptsInput = false
        let sendQueued =
            returningInput && interruptedByPerson && options.interruptSendsQueued != .none
            && !pending.isEmpty && state.exitRequest == nil
        if sendQueued {
            returningInput = false
            interruptedByPerson = false
            return startQueued(offeringRest: options.interruptSendsQueued == .all)
        }
        if returningInput {
            interruptedByPerson = false
            for prompt in pending where state.transcript.items.indices.contains(prompt.transcriptIndex) {
                if state.transcript.items[prompt.transcriptIndex] == .queued(prompt.text) {
                    state.transcript.finishProgress(at: prompt.transcriptIndex)
                }
            }
            let texts = pending.map(\.text) + (state.editor.text.isEmpty ? [] : [state.editor.text])
            state.editor.restore(texts.joined(separator: "\n\n"))
            pending.removeAll()
            returningInput = false
            return []
        }
        guard !pending.isEmpty, state.exitRequest == nil else { return [] }
        // A message may arrive after the agent's last boundary but before runEnded reaches the screen.
        // It is still ours until acknowledged, so start it now and reoffer the others to the new run.
        return startQueued(offeringRest: true)
    }

    /// Starts a turn with the first queued message, steering before follow-ups. The others join that turn as steering, or, when
    /// `offeringRest` is false, wait here and start their own turns one by one as each ends.
    private mutating func startQueued(offeringRest: Bool) -> [Effect] {
        let index = pending.firstIndex(where: { !$0.followUp }) ?? pending.startIndex
        let first = pending[index]
        replaceQueuedPrompt(id: first.id, text: first.text)
        return begin(.startRun(first.text)) + (offeringRest ? pending.map(\.effect) : [])
    }

    /// Puts `text` in the editor if the person has written nothing there; otherwise keeps their draft and shows the text in a notice.
    mutating func fill(draft text: String) {
        guard state.editor.text.allSatisfy(\.isWhitespace) else {
            state.transcript.addNotice("Your draft was kept. The prompt you went back to was:\n\(text)", isError: false)
            return
        }
        state.editor.restore(text)
    }

    /// Replaces the queued steering notification with the user message in-place to avoid duplicate transcript noise.
    mutating func replaceQueuedPrompt(id: Int, text: String) {
        guard let pendingIndex = pending.firstIndex(where: { $0.id == id }) else { return }
        let prompt = pending.remove(at: pendingIndex)
        let index = prompt.transcriptIndex
        // Still the queued message it was: the spinner moves the revision on every tick, so the item is checked, not the revision.
        guard state.transcript.items.indices.contains(index), state.transcript.items[index] == .queued(prompt.text)
        else {
            state.transcript.addUser(text)
            return
        }
        state.transcript.items[index] = .user(text)
        state.transcript.progress[index] = nil
        state.transcript.revisions[index] = state.transcript.bump()
    }
}
