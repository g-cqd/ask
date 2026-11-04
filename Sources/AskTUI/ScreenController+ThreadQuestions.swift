/// Where a thread's question appears while the person is elsewhere (roadmap 0195, note n19, `threads.questions`): `focus` shows it at
/// once in whatever is shown, named for its thread; `after` once it has waited its delay; `lane` only in its lane. A popped question is
/// a copy: its thread keeps its own until it is answered, so a lane opened or left never carries it into the wrong view.
extension ScreenController {
    /// Shows a waiting thread's question in what is shown, when that asks nothing itself and the setting allows it now.
    mutating func popThreadQuestion(at instant: ContinuousClock.Instant = .now) {
        guard state.popped == nil, state.pendingApproval == nil, state.pendingQuestions == nil else { return }
        let shown = state.lane?.isThread == true ? state.lane?.id : nil
        for runner in state.runners where runner.kind == .agent && runner.id != shown {
            guard let view = state.threads[runner.id], view.approval != nil || view.questions != nil else { continue }
            switch options.threadQuestions {
                case .lane: return
                case .after(let delay):
                    guard let asked = state.threadAskedAt[runner.id], instant - asked >= delay else { continue }
                case .focus: break
            }
            if let approval = view.approval {
                state.pendingApproval = PendingApproval(
                    id: approval.id,
                    question: "\(runner.name): " + approval.question,
                    kind: approval.kind,
                    detail: approval.detail
                )
            } else {
                state.pendingQuestions = view.questions
            }
            state.popped = runner.id
            return
        }
    }

    /// Takes a popped question back off what is shown; its thread still has it.
    mutating func unpopThreadQuestion() {
        guard state.popped != nil else { return }
        state.pendingApproval = nil
        state.pendingQuestions = nil
        state.popped = nil
    }

    /// What is shown answered its question: a popped one is its thread's, which asks it no more; then the next may pop.
    mutating func questionSettled() {
        if let id = state.popped {
            state.threads[id]?.approval = nil
            state.threads[id]?.questions = nil
            state.popped = nil
        }
        popThreadQuestion()
    }

    /// The delay of `threads.questions` `after` has passed for what threads asked by `instant`.
    mutating func threadQuestionDelayEnded(at instant: ContinuousClock.Instant = .now) {
        popThreadQuestion(at: instant)
    }

    /// When `update`, for thread `id`, asks the person: noted for `after`, which arms its timer.
    mutating func noteThreadAsks(_ id: String, _ update: ConversationUpdate) -> [Effect] {
        switch update {
            case .askApproval, .askQuestions:
                state.threadAskedAt[id] = .now
                if case .after(let delay) = options.threadQuestions { return [.armThreadQuestionTimer(after: delay)] }
                return []
            default: return []
        }
    }
}
