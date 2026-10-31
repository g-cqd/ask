internal import TerminalKitCodecs
internal import TerminalKitInput

/// The model's questions (roadmap 0117, redesigned 2026-10-31), in the approval section's place: Tab and Shift+Tab move the focus between
/// the tabs, the choices and the note row; on the tabs Left and Right change question, on the choices Up and Down highlight and Space or
/// a number checks, and the note row edits as the input does. Enter goes on (after the last of a series, to a review that Enter sends and
/// Esc leaves), Esc on a question declines them all, Ctrl+C declines and stops the turn. The input keeps its draft and takes no key.
extension ScreenController {
    mutating func askQuestions(id: Int, questions: [ScreenQuestion]) {
        guard !questions.isEmpty else { return }
        state.pendingQuestions = PendingQuestions(id: id, questions: questions)
        state.scrollback = 0
    }

    /// What a key does to the questions; nil when no question waits, or in a lane for any key but Esc.
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
        switch key.keyCode {
            case 0x1B: return finish(pending, with: nil)
            case 0x0D where !key.modifiers.contains(.shift): return enter(&pending)
            case 0x09: pending.moveFocus(by: key.modifiers.contains(.shift) ? -1 : 1)
            default:
                switch pending.focus {
                    case .tabs: tabsKey(key, &pending)
                    case .choices: choicesKey(key, &pending)
                    case .note: noteKey(key, &pending)
                }
        }
        state.pendingQuestions = pending
        return []
    }

    /// On the tabs: Left and Right show the question before or after, Right after the last the review.
    private mutating func tabsKey(_ key: KeyEvent, _ pending: inout PendingQuestions) {
        switch key.keyCode {
            case Key.left.rawValue: show(pending.current - 1, in: &pending, focus: .tabs)
            case Key.right.rawValue where pending.current == pending.questions.count - 1: pending.reviewing = true
            case Key.right.rawValue: show(pending.current + 1, in: &pending, focus: .tabs)
            case Key.down.rawValue: pending.moveFocus(by: 1)
            default: break
        }
    }

    /// On the choices: Up and Down highlight (past the first, the tabs; past the last, the note), Space or a number checks.
    private func choicesKey(_ key: KeyEvent, _ pending: inout PendingQuestions) {
        let count = pending.questions[pending.current].choices.count
        let cursor = pending.cursors[pending.current]
        switch key.keyCode {
            case Key.up.rawValue where cursor == 0: if pending.isSeries { pending.focus = .tabs }
            case Key.up.rawValue: pending.cursors[pending.current] = cursor - 1
            case Key.down.rawValue where cursor >= count - 1:
                if pending.questions[pending.current].note != .none { pending.focus = .note }
            case Key.down.rawValue: pending.cursors[pending.current] = cursor + 1
            case 0x20: check(cursor, in: &pending)
            default:
                guard key.modifiers.isEmpty, let scalar = Unicode.Scalar(key.keyCode),
                    let number = Character(scalar).wholeNumberValue, (1 ... Swift.max(1, count)).contains(number)
                else { return }
                pending.cursors[pending.current] = number - 1
                check(number - 1, in: &pending)
        }
    }

    /// On the note row: the input's editing keys; Up from its first row goes back to the choices.
    private func noteKey(_ key: KeyEvent, _ pending: inout PendingQuestions) {
        let outcome = pending.notes[pending.current].apply(key)
        if outcome == .ignored, key.keyCode == Key.up.rawValue, !pending.questions[pending.current].choices.isEmpty {
            pending.focus = .choices
        }
    }

    /// In the review, Enter sends and Esc goes back to the last question; nothing is typed.
    private mutating func reviewKey(_ key: KeyEvent, _ pending: inout PendingQuestions) -> [Effect] {
        switch key.keyCode {
            case 0x0D: return finish(pending, with: pending.answers)
            case 0x1B, Key.left.rawValue: pending.reviewing = false
            default: break
        }
        state.pendingQuestions = pending
        return []
    }

    /// Enter: the next question, or the review after the last of a series, or the answer; a required note holds it.
    private mutating func enter(_ pending: inout PendingQuestions) -> [Effect] {
        let question = pending.questions[pending.current]
        if question.note == .required, PendingQuestions.trimmed(pending.notes[pending.current].text).isEmpty {
            pending.problem = "This question needs a note: Tab to the note row and type it."
            pending.focus = .note
            state.pendingQuestions = pending
            return []
        }
        if pending.current < pending.questions.count - 1 {
            show(pending.current + 1, in: &pending)
        } else if pending.isSeries {
            pending.reviewing = true
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

    /// A click on row `index` under the question shown: a choice is checked, as Space would; a row of the note focuses it (roadmap 0117).
    mutating func clickQuestion(choice index: Int) {
        guard var pending = state.pendingQuestions, !pending.reviewing, index >= 0 else { return }
        let question = pending.questions[pending.current]
        if question.choices.indices.contains(index) {
            pending.cursors[pending.current] = index
            pending.focus = .choices
            check(index, in: &pending)
        } else if question.note != .none {
            pending.focus = .note
        }
        state.pendingQuestions = pending
    }

    /// A click on tab `index`: that question, or the review after the last.
    mutating func clickQuestionTab(_ index: Int) {
        guard var pending = state.pendingQuestions else { return }
        if pending.reviewing {
            guard pending.questions.indices.contains(index) else { return }
            pending.reviewing = false
            pending.current = index
            pending.focus = PendingQuestions.opening(pending.questions[index])
        } else if index == pending.questions.count {
            pending.reviewing = true
        } else {
            show(index, in: &pending)
        }
        state.pendingQuestions = pending
    }

    /// Shows question `index`, focused on `focus`, or where it opens.
    private func show(_ index: Int, in pending: inout PendingQuestions, focus: PendingQuestions.Focus? = nil) {
        guard pending.questions.indices.contains(index), index != pending.current else { return }
        pending.current = index
        pending.focus = focus ?? PendingQuestions.opening(pending.questions[index])
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

    /// Ends the questions with `answers` (nil: declined).
    private mutating func finish(_ pending: PendingQuestions, with answers: [QuestionAnswer]?) -> [Effect] {
        state.pendingQuestions = nil
        return [.answerQuestions(id: pending.id, answers)]
    }

    /// The run ended: whatever still waited on the person goes, questions included.
    mutating func runEnded() -> [Effect] {
        state.compacting = false
        state.reconnecting = false
        state.connectingMCP = false
        state.waitingForNetwork = false
        state.transcript.finishRunProgress()
        state.pendingApproval = nil
        state.pendingQuestions = nil
        // A question a command beside the run asked is that command's to take away (roadmap 0113).
        if runOwnsQuestion {
            state.pendingInput = nil
            state.inputAnswer.clear()
        }
        return endRun()
    }
}
