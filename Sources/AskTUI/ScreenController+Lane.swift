/// A focused runner (roadmap 0062, step 2): its output takes the transcript, the main conversation waits inside ``LaneView``, and Esc puts it back.
/// A job has no conversation, so the one input still sends to main and says so in the status line; what is typed is never sent to a runner.
extension ScreenController {
    /// Runs `change` with the main conversation as the transcript, then puts the lane back. Updates from a run belong to main whatever is shown.
    mutating func onMain<T>(_ change: (inout ScreenController) -> T) -> T {
        guard state.lane != nil else { return change(&self) }
        swapLane()
        let result = change(&self)
        swapLane()
        // The runner may have ended meanwhile: the lane is left to main with a notice if auto-return is on.
        if let lane = state.lane, !state.runners.contains(where: { $0.id == lane.id }) {
            if options.jobAutoReturnWhenFocused {
                leaveLane(notice: "\(lane.name) is no longer running; back to main.")
            }
        }
        return result
    }

    /// An update from the conversation. A runner's output belongs to the lane that asked for it; everything else belongs to main.
    mutating func deliver(_ update: ConversationUpdate) -> [Effect] {
        if case .runnerOutput(let id, let text) = update {
            receive(output: text, of: id)
            return []
        }
        // A lane changes outside ``onMain(_:)``, which puts the lane back around what it applies.
        if case .focusThread(let id) = update {
            guard let runner = state.runners.first(where: { $0.id == id && $0.kind == .agent }) else { return [] }
            return enterLane(runner)
        }
        // A popped question is taken off around the update, which may bring what is shown a question of its own, then may pop again.
        unpopThreadQuestion()
        var effects = onMain { $0.holdingView { $0.apply(update) } }
        if case .thread(let id, let inner) = update {
            // A thread's events are its activity: the sidebar spins for it while they come (note n15).
            state.runnerActivity[id] = .now
            effects += noteThreadAsks(id, inner)
        }
        popThreadQuestion()
        return effects
    }

    /// Shows `runner`'s output in place of the conversation and asks for it.
    mutating func enterLane(_ runner: RunnerInfo) -> [Effect] {
        leaveLane()
        unpopThreadQuestion()
        defer { popThreadQuestion() }
        if runner.kind == .agent { return enterThread(runner) }
        state.laneSerial += 1
        var view = Transcript(revisionBase: state.laneSerial << 40)
        view.addNotice("\(runner.name) · reading its output…", isError: false)
        state.lane = LaneView(
            id: runner.id,
            name: runner.name,
            stashed: state.transcript,
            stashedScrollback: state.scrollback
        )
        state.transcript = view
        state.scrollback = 0
        state.stripSelection = nil
        clearSelection()
        return [.readRunnerOutput(id: runner.id)]
    }

    /// Puts the main conversation back, as it was, and says `notice` there if given. Nothing happens when no lane is focused.
    mutating func leaveLane(notice: String? = nil) {
        guard let lane = state.lane else { return }
        unpopThreadQuestion()
        defer { popThreadQuestion() }
        clearSelection()
        // A thread's conversation and questions are kept for the next time its lane is shown; main's come back.
        if lane.isThread {
            state.threads[lane.id] = ThreadView(
                transcript: state.transcript,
                approval: state.pendingApproval,
                questions: state.pendingQuestions
            )
            state.pendingApproval = lane.stashedApproval
            state.pendingQuestions = lane.stashedQuestions
        }
        state.transcript = lane.stashed
        state.scrollback = lane.stashedScrollback
        state.lane = nil
        if let notice { state.transcript.addNotice(notice, isError: false) }
    }

    /// The output arrived. It replaces the placeholder, unless the user has moved on to another lane or to main.
    mutating func receive(output text: String, of id: String) {
        guard state.lane?.id == id else { return }
        state.transcript.removeAll()
        state.transcript.addNotice(text.isEmpty ? "(no output yet)" : OutputEscapes(text).text, isError: false)
    }

    private mutating func swapLane() {
        guard var lane = state.lane else { return }
        swap(&lane.stashed, &state.transcript)
        swap(&lane.stashedScrollback, &state.scrollback)
        if lane.isThread {
            swap(&lane.stashedApproval, &state.pendingApproval)
            swap(&lane.stashedQuestions, &state.pendingQuestions)
        }
        state.lane = lane
    }
}
