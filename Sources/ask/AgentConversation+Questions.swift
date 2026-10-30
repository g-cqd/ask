internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// The model's questions (roadmap 0117): put to the person on the screen, in the approval section's place, and answered there.
extension AgentConversation {
    /// Asks `questions` and waits; nil when the person declines, the turn is stopped, or no one is there to ask.
    func askPerson(_ questions: [PersonQuestion]) async -> [PersonAnswer]? {
        let id = approvals.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        let shown = questions.map(Self.screenQuestion)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (answer: CheckedContinuation<[PersonAnswer]?, Never>) in
                let ask = approvals.withLock { state in
                    state.questions[id] = answer
                    return state.ask
                }
                if Task.isCancelled { return settleQuestions(id, with: nil) }
                guard let ask else { return settleQuestions(id, with: nil) }
                ask(.askQuestions(id: id, questions: shown))
            }
        } onCancel: {
            settleQuestions(id, with: nil)
        }
    }

    func answer(questions id: Int, with answers: [QuestionAnswer]?) {
        settleQuestions(id, with: answers.map { $0.map { PersonAnswer(chosen: $0.chosen, note: $0.note) } })
    }

    /// Answers question set `id` once; a second answer does nothing.
    private func settleQuestions(_ id: Int, with answers: [PersonAnswer]?) {
        let waiting = approvals.withLock { $0.questions.removeValue(forKey: id) }
        waiting?.resume(returning: answers)
    }

    private static func screenQuestion(_ question: PersonQuestion) -> ScreenQuestion {
        let note: ScreenQuestion.Note =
            switch question.note {
                case .optional: .optional
                case .required: .required
                case .none: .none
            }
        return ScreenQuestion(
            question: question.question, header: question.header,
            choices: question.choices.map { ScreenQuestion.Choice(label: $0.label, detail: $0.description) },
            multiple: question.multiple, note: note)
    }
}
