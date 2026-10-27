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
        return onMain { $0.holdingView { $0.apply(update) } }
    }

    /// Shows `runner`'s output in place of the conversation and asks for it.
    mutating func enterLane(_ runner: RunnerInfo) -> [Effect] {
        leaveLane()
        state.laneSerial += 1
        var view = Transcript(revisionBase: state.laneSerial << 40)
        view.addNotice("\(runner.name) · reading its output…", isError: false)
        state.lane = LaneView(
            id: runner.id, name: runner.name, stashed: state.transcript, stashedScrollback: state.scrollback)
        state.transcript = view
        state.scrollback = 0
        state.stripSelection = nil
        clearSelection()
        return [.readRunnerOutput(id: runner.id)]
    }

    /// Puts the main conversation back, as it was, and says `notice` there if given. Nothing happens when no lane is focused.
    mutating func leaveLane(notice: String? = nil) {
        guard let lane = state.lane else { return }
        clearSelection()
        state.transcript = lane.stashed
        state.scrollback = lane.stashedScrollback
        state.lane = nil
        if let notice { state.transcript.addNotice(notice, isError: false) }
    }

    /// The output arrived. It replaces the placeholder, unless the user has moved on to another lane or to main.
    mutating func receive(output text: String, of id: String) {
        guard state.lane?.id == id else { return }
        state.transcript.removeAll()
        state.transcript.addNotice(text.isEmpty ? "(no output yet)" : text, isError: false)
    }

    private mutating func swapLane() {
        guard var lane = state.lane else { return }
        swap(&lane.stashed, &state.transcript)
        swap(&lane.stashedScrollback, &state.scrollback)
        state.lane = lane
    }
}
