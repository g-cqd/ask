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
        markChoicesStale()
        state.running = false
        state.abortArmedAt = nil
        state.abortArmedAction = nil
        acceptsInput = false
        // A command typed during the turn that waited for its end goes first (roadmap 0113).
        if startsWaitingCommand { return startWaitingCommand() }
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
            let returned = (pending.map { (index: $0.transcriptIndex, text: $0.text) } + takeWaitingCommands())
                .sorted { $0.index < $1.index }
            for item in returned where state.transcript.items.indices.contains(item.index) {
                if state.transcript.items[item.index] == .queued(item.text) {
                    state.transcript.finishProgress(at: item.index)
                }
            }
            let texts = returned.map(\.text) + (state.editor.text.isEmpty ? [] : [state.editor.text])
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

    /// A queued message the conversation did not take: no longer waiting, said so where it stood, and back in the input.
    mutating func refuseQueuedPrompt(id: Int) {
        guard let pendingIndex = pending.firstIndex(where: { $0.id == id }) else { return }
        let prompt = pending.remove(at: pendingIndex)
        let index = prompt.transcriptIndex
        if state.transcript.items.indices.contains(index), state.transcript.items[index] == .queued(prompt.text) {
            state.transcript.replace(at: index, with: .notice("Not sent: \(prompt.text)", isError: true))
        }
        fill(draft: prompt.text)
    }

    /// Replaces the queued steering notification with the user message in-place to avoid duplicate transcript noise.
    mutating func replaceQueuedPrompt(id: Int, text: String) {
        guard let pendingIndex = pending.firstIndex(where: { $0.id == id }) else { return }
        let prompt = pending.remove(at: pendingIndex)
        showSent(at: prompt.transcriptIndex, queued: prompt.text, as: text)
    }
}
