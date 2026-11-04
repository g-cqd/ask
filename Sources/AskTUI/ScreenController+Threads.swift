/// Threads (roadmap 0194): each one's conversation is a transcript of its own, filled by its updates whether or not its lane is shown;
/// in its lane, the input talks to it.
extension ScreenController {
    /// An update from thread `id`, drawn in its conversation. During ``onMain(_:)`` the lane's view waits in the lane, so a thread whose
    /// lane is shown is changed there. Only what a conversation shows applies: a thread's run, status or questions are not main's.
    mutating func applyThread(_ id: String, _ update: ConversationUpdate) -> [Effect] {
        let inLane = state.lane?.isThread == true && state.lane?.id == id
        var thread: Transcript
        if inLane, let lane = state.lane {
            thread = lane.stashed
            state.lane?.stashed = Transcript()
        } else {
            thread = state.threads.removeValue(forKey: id) ?? newThreadTranscript()
        }
        swap(&thread, &state.transcript)
        let effects = applyInThread(update)
        swap(&thread, &state.transcript)
        if inLane { state.lane?.stashed = thread } else { state.threads[id] = thread }
        return effects
    }

    /// Shows thread `runner`'s conversation in place of main's.
    mutating func enterThread(_ runner: RunnerInfo) -> [Effect] {
        let view = state.threads.removeValue(forKey: runner.id) ?? newThreadTranscript()
        state.lane = LaneView(
            id: runner.id,
            name: runner.name,
            stashed: state.transcript,
            stashedScrollback: state.scrollback,
            isThread: true
        )
        state.transcript = view
        state.scrollback = 0
        state.stripSelection = nil
        clearSelection()
        return []
    }

    /// What is typed in a thread's lane goes to the thread, shown in its conversation; nil outside one.
    mutating func sendToThread(_ text: String) -> [Effect]? {
        guard let lane = state.lane, lane.isThread else { return nil }
        state.transcript.addUser(text)
        state.scrollback = 0
        return [.sendToThread(id: lane.id, text: text)]
    }

    private mutating func newThreadTranscript() -> Transcript {
        state.laneSerial += 1
        return state.transcript.emptyLike(revisionBase: state.laneSerial << 40)
    }

    /// The thread's conversation is the transcript while this runs, so what changes only a transcript is main's own handling.
    private mutating func applyInThread(_ update: ConversationUpdate) -> [Effect] {
        switch update {
            // Not main's history of sent lines: the thread's task is its own.
            case .userPrompt(let text): state.transcript.addUser(text)
            case .assistantText, .thinkingText, .toolStarted, .toolFinished, .toolProgress, .jobOutput, .notice:
                return apply(update)
            case .runEnded: state.transcript.finishRunProgress()
            default: break
        }
        return []
    }
}
