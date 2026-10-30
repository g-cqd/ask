internal import TerminalKitCodecs
internal import TerminalKitInput

/// The model's questions (roadmap 0117), in the approval section's place: Up and Down move, Space or a number checks while the note is
/// empty, what is typed in the input is the question's note, Tab and Shift+Tab change question, Enter goes on (after the last of a
/// series, to a review that Enter sends and Esc leaves), Esc on a question declines them all, Ctrl+C declines and stops the turn.
extension ScreenController {
    mutating func askQuestions(id: Int, questions: [ScreenQuestion]) {
        guard !questions.isEmpty else { return }
        state.pendingQuestions = PendingQuestions(id: id, questions: questions, draft: state.editor.text)
        state.editor = PromptEditor()
        state.scrollback = 0
    }

    /// What a key does to the questions; nil when it is the note's, for the input.
    mutating func questionKey(_ key: KeyEvent) -> [Effect]? {
        guard var pending = state.pendingQuestions else { return nil }
        if key.keyCode == 0x03 || (key.modifiers.contains(.ctrl) && (key.keyCode == 0x63 || key.keyCode == 0x43)) {
            return finish(pending, with: nil) + abort()
        }
        // In a lane the section is not shown: Esc returns to it, and the lane keeps its other keys.
        if state.lane != nil {
            guard key.keyCode == 0x1B else { return nil }
            leaveLane()
            return []
        }
        pending.problem = nil
        if pending.reviewing { return reviewKey(key, &pending) }
        let noteIsEmpty = state.editor.text.isEmpty
        let count = pending.questions[pending.current].choices.count
        switch key.keyCode {
            case 0x1B: return finish(pending, with: nil)
            case 0x0D: return enter(&pending)
            case 0x09: show(pending.current + (key.modifiers.contains(.shift) ? -1 : 1), in: &pending)
            case Key.up.rawValue: pending.cursors[pending.current] = Swift.max(0, pending.cursors[pending.current] - 1)
            case Key.down.rawValue:
                pending.cursors[pending.current] = Swift.min(
                    Swift.max(0, count - 1), pending.cursors[pending.current] + 1)
            case 0x20 where noteIsEmpty && count > 0: check(pending.cursors[pending.current], in: &pending)
            default:
                guard noteIsEmpty, key.modifiers.isEmpty, let scalar = Unicode.Scalar(key.keyCode),
                    let number = Character(scalar).wholeNumberValue, (1 ... Swift.max(1, count)).contains(number),
                    count > 0
                else { return pending.questions[pending.current].note == .none ? [] : nil }
                pending.cursors[pending.current] = number - 1
                check(number - 1, in: &pending)
        }
        state.pendingQuestions = pending
        return []
    }

    /// In the review, Enter sends and Esc goes back to the last question; nothing is typed.
    private mutating func reviewKey(_ key: KeyEvent, _ pending: inout PendingQuestions) -> [Effect] {
        switch key.keyCode {
            case 0x0D: return finish(pending, with: pending.answers)
            case 0x1B:
                pending.reviewing = false
                state.editor = Self.editor(holding: pending.notes[pending.current])
            default: break
        }
        state.pendingQuestions = pending
        return []
    }

    /// Enter: the next question, or the review after the last of a series, or the answer; a required note holds it.
    private mutating func enter(_ pending: inout PendingQuestions) -> [Effect] {
        pending.notes[pending.current] = state.editor.text
        let question = pending.questions[pending.current]
        if question.note == .required, PendingQuestions.trimmed(state.editor.text).isEmpty {
            pending.problem = "This question needs a note: type it in the input."
            state.pendingQuestions = pending
            return []
        }
        if pending.current < pending.questions.count - 1 {
            show(pending.current + 1, in: &pending)
        } else if pending.isSeries {
            pending.reviewing = true
            state.editor = PromptEditor()
        } else {
            return finish(pending, with: pending.answers)
        }
        state.pendingQuestions = pending
        return []
    }

    /// A click in the section above the input: an approval's answer or command, or one of the model's choices or tabs (roadmap 0117).
    mutating func clickSection(detail: Bool, at cell: CellPosition) {
        let row = cell.row - frame.approvalAnswers.lowerBound
        switch (detail, state.pendingQuestions != nil) {
            case (true, false): toggleApprovalDetail()
            case (true, true):
                if let tab = frame.questionTabs.firstIndex(where: { $0.contains(cell.col) }) { clickQuestionTab(tab) }
            case (false, false): checkApproval(answer: row)
            case (false, true): clickQuestion(choice: row)
        }
    }

    /// A click on choice `index` of the question shown: it is checked, as Space would, whatever the note holds (roadmap 0117).
    mutating func clickQuestion(choice index: Int) {
        guard var pending = state.pendingQuestions, !pending.reviewing,
            pending.questions[pending.current].choices.indices.contains(index)
        else { return }
        pending.cursors[pending.current] = index
        check(index, in: &pending)
        state.pendingQuestions = pending
    }

    /// A click on tab `index`: that question, or the review after the last.
    mutating func clickQuestionTab(_ index: Int) {
        guard var pending = state.pendingQuestions else { return }
        if pending.reviewing {
            guard pending.questions.indices.contains(index) else { return }
            pending.reviewing = false
            pending.current = index
            state.editor = Self.editor(holding: pending.notes[index])
        } else if index == pending.questions.count {
            pending.notes[pending.current] = state.editor.text
            pending.reviewing = true
            state.editor = PromptEditor()
        } else {
            show(index, in: &pending)
        }
        state.pendingQuestions = pending
    }

    /// Shows question `index`, keeping the note of the one left and putting its own in the input.
    private mutating func show(_ index: Int, in pending: inout PendingQuestions) {
        guard pending.questions.indices.contains(index), index != pending.current else { return }
        pending.notes[pending.current] = state.editor.text
        pending.current = index
        state.editor = Self.editor(holding: pending.notes[index])
    }

    /// Checks choice `index`: one of several toggles; the only one replaces what was checked.
    private func check(_ index: Int, in pending: inout PendingQuestions) {
        let current = pending.current
        if pending.questions[current].multiple {
            if pending.chosen[current].contains(index) {
                pending.chosen[current].remove(index)
            } else {
                pending.chosen[current].insert(index)
            }
        } else {
            pending.chosen[current] = [index]
        }
    }

    /// Ends the questions with `answers` (nil: declined) and gives the input back its draft.
    private mutating func finish(_ pending: PendingQuestions, with answers: [QuestionAnswer]?) -> [Effect] {
        state.pendingQuestions = nil
        state.editor = Self.editor(holding: pending.draft)
        return [.answerQuestions(id: pending.id, answers)]
    }

    /// The run ended: whatever still waited on the person goes, questions included, and the input gets its draft back.
    mutating func runEnded() -> [Effect] {
        state.compacting = false
        state.reconnecting = false
        state.connectingMCP = false
        state.waitingForNetwork = false
        state.transcript.finishRunProgress()
        state.pendingApproval = nil
        if let pending = state.pendingQuestions {
            state.pendingQuestions = nil
            state.editor = Self.editor(holding: pending.draft)
        }
        state.pendingInput = nil
        state.inputAnswer.clear()
        return endRun()
    }

    private static func editor(holding text: String) -> PromptEditor {
        var editor = PromptEditor()
        if !text.isEmpty { editor.paste(text) }
        return editor
    }
}
