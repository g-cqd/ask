import AskTUI
import Synchronization

/// A conversation the test directs: it says what was asked of it, and the test says what it tells its driver and when it ends.
final class DirectedConversation: Conversation {
    /// What the driver asked of the conversation.
    enum Asked: Sendable, Equatable {
        case started(String)
        case enqueued(String, id: Int, followUp: Bool)
        case answeredApproval(Int, ApprovalChoice)
        /// The questions `id` asked were answered, or declined (nil).
        case answeredQuestions(Int, [QuestionAnswer]?)
        case answeredInput(Int, String?)
        /// The run that last started was cancelled, as Esc cancels it.
        case stopped
    }

    private let asked = Mailbox<Asked>()
    private let log = Mutex<[Asked]>([])

    /// Everything the driver has asked so far, in order.
    var everything: [Asked] { log.withLock { $0 } }
    private let update = Mutex<(@Sendable (ConversationUpdate) -> Void)?>(nil)

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        self.update.withLock { $0 = update }
        note(.started(prompt))
        // The run: it does nothing, and says so when it is cancelled. A stream nobody feeds ends only by cancellation.
        return Task { [weak self] in
            let (never, _) = AsyncStream<Void>.makeStream()
            for await _ in never {}
            if Task.isCancelled { self?.note(.stopped) }
        }
    }

    func enqueue(_ text: String, id: Int, followUp: Bool) { note(.enqueued(text, id: id, followUp: followUp)) }

    func answer(approval id: Int, with choice: ApprovalChoice) { note(.answeredApproval(id, choice)) }

    func answer(questions id: Int, with answers: [QuestionAnswer]?) {
        note(.answeredQuestions(id, answers))
    }

    func answer(input id: Int, with text: String?) { note(.answeredInput(id, text)) }

    private func note(_ asked: Asked) {
        log.withLock { $0.append(asked) }
        self.asked.post(asked)
    }

    /// The next thing the driver asked, awaited; nil when the test is cancelled first.
    func next() async -> Asked? { await asked.next() }

    /// Tells the driver of the turn that last started.
    func say(_ updates: ConversationUpdate...) {
        let update = update.withLock { $0 }
        for one in updates { update?(one) }
    }
}
