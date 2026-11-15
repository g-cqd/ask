import AskTUI
import Synchronization

/// A conversation the test directs: it says what was asked of it, and the test says what it tells its driver and when it ends.
final class DirectedConversation: Conversation {
    /// What the driver asked of the conversation.
    enum Asked: Sendable, Equatable {
        case started(String)
        case enqueued(String, id: Int, followUp: Bool)
    }

    private let asked = Mailbox<Asked>()
    private let update = Mutex<(@Sendable (ConversationUpdate) -> Void)?>(nil)

    func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
        self.update.withLock { $0 = update }
        asked.post(.started(prompt))
        return Task {}
    }

    func enqueue(_ text: String, id: Int, followUp: Bool) { asked.post(.enqueued(text, id: id, followUp: followUp)) }

    /// The next thing the driver asked, awaited; nil when the test is cancelled first.
    func next() async -> Asked? { await asked.next() }

    /// Tells the driver of the turn that last started.
    func say(_ updates: ConversationUpdate...) {
        let update = update.withLock { $0 }
        for one in updates { update?(one) }
    }
}
