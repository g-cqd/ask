/// Threads (roadmap 0194): each one's conversation is a transcript of its own, filled by its updates whether or not its lane is shown;
/// in its lane, the input talks to it.
extension ScreenController {
    /// An update from thread `id`, drawn in its conversation. During ``onMain(_:)`` the lane's view waits in the lane, so a thread whose
    /// lane is shown is changed there. Only what a conversation shows applies: a thread's run, status or questions are not main's.
    mutating func applyThread(_ id: String, _ update: ConversationUpdate) -> [Effect] {
        let inLane = state.lane?.isThread == true && state.lane?.id == id
        var thread: ThreadView
        if inLane, let lane = state.lane {
            thread = ThreadView(
                transcript: lane.stashed,
                approval: lane.stashedApproval,
                questions: lane.stashedQuestions
            )
            state.lane?.stashed = Transcript()
        } else {
            thread = state.threads.removeValue(forKey: id) ?? ThreadView(transcript: newThreadTranscript())
        }
        // The thread's view stands in for main's while its update applies; main's scroll position is not the thread's to move.
        let scrollback = state.scrollback
        swapView(&thread)
        let effects = applyInThread(update)
        swapView(&thread)
        state.scrollback = scrollback
        if inLane {
            state.lane?.stashed = thread.transcript
            state.lane?.stashedApproval = thread.approval
            state.lane?.stashedQuestions = thread.questions
        } else {
            state.threads[id] = thread
        }
        return effects
    }

    private mutating func swapView(_ thread: inout ThreadView) {
        swap(&thread.transcript, &state.transcript)
        swap(&thread.approval, &state.pendingApproval)
        swap(&thread.questions, &state.pendingQuestions)
    }

    /// Shows thread `runner`'s conversation in place of main's.
    mutating func enterThread(_ runner: RunnerInfo) -> [Effect] {
        let view = state.threads.removeValue(forKey: runner.id) ?? ThreadView(transcript: newThreadTranscript())
        state.lane = LaneView(
            id: runner.id,
            name: runner.name,
            stashed: state.transcript,
            stashedScrollback: state.scrollback,
            isThread: true,
            stashedApproval: state.pendingApproval,
            stashedQuestions: state.pendingQuestions
        )
        state.transcript = view.transcript
        state.pendingApproval = view.approval
        state.pendingQuestions = view.questions
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
            // The thread's own questions too (roadmap 0195): its view is the screen's here, so they land in its section.
            case .assistantText, .thinkingText, .toolStarted, .toolFinished, .toolProgress, .jobOutput, .notice,
                .askApproval,
                .askQuestions:
                return apply(update)
            // Its run's end takes away what it still asked.
            case .runEnded:
                state.transcript.finishRunProgress()
                state.pendingApproval = nil
                state.pendingQuestions = nil
            default: break
        }
        return []
    }
}
