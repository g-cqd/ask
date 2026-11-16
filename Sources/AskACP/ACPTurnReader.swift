internal import AemiJSON
internal import AskTUI

/// One turn as it is read (ACP v1, Prompt Turn): each thing the conversation says is told to the client before the next is read,
/// so the client sees them in the order they were said, and an approval is asked of it where the screen would ask the person.
struct ACPTurnReader {
    /// A call that began and has not ended: the title it was given, and whether its progress has been said on it.
    struct Call {
        let id: String
        let title: String
        /// The change it makes to a file, which a client shows as a diff, when it is an edit.
        var change: JSONValue?
        var progressed = false
    }

    let session: ACPSession
    let client: ACPClient
    /// Whether the turn is a command's (``ACPCommands``): what it says to the person is then its answer.
    let answers: Bool
    private(set) var failed = false
    /// The last error said before something else was, and the one said just now, which may be a refused message's reason.
    private var settled: String?
    private var recent: String?
    /// The messages refused with no reason given yet: a hook's refusal comes before its reason.
    private var unexplained: [Int] = []
    /// The calls that began and have not ended, oldest first.
    var running: [Call] = []
    /// The compaction that began and has not ended.
    var compaction: String?

    init(session: ACPSession, client: ACPClient, answers: Bool = false) {
        self.session = session
        self.client = client
        self.answers = answers
    }

    /// Why the turn failed, when it did: the last error it said.
    var failure: String? { recent ?? settled }

    /// Reads one update; false when it ended the turn. `turns` is told what became of a prompt sent during the turn.
    mutating func read(_ update: ConversationUpdate, in turns: ACPTurns) async -> Bool {
        switch update {
            case .runEnded: return false
            case .returnQueuedPrompts: failed = true
            case .promptAccepted(let id, _): turns.take(id)
            case .promptRefused, .notice(_, isError: true): await refusal(update, in: turns)
            default: await show(update, in: turns)
        }
        // An error is a refused message's reason only when the two are said together.
        if case .promptRefused = update {
        } else if case .notice(_, isError: true) = update {
        } else if let said = recent {
            (settled, recent) = (said, nil)
        }
        return true
    }

    /// A message the conversation refused, and the error that says why, in either order: a skill that cannot be loaded gives its
    /// reason and then refuses; a hook that blocks a message refuses and then gives its reason.
    private mutating func refusal(_ update: ConversationUpdate, in turns: ACPTurns) async {
        switch update {
            case .promptRefused(let id):
                guard let reason = recent else { return unexplained.append(id) }
                turns.refuse(id, because: reason)
                recent = nil
            case .notice(let reason, _):
                if unexplained.isEmpty {
                    if let said = recent { settled = said }
                    recent = reason
                } else {
                    for id in unexplained { turns.refuse(id, because: reason) }
                    unexplained = []
                }
                await show(update, in: turns)
            default: break
        }
    }

    /// What is left when the turn has ended: a refused message nobody gave a reason for is answered, and a compaction that was
    /// still running is said to have been stopped, since one that was reported must be reported as ended.
    mutating func end(in turns: ACPTurns) async {
        for id in unexplained { turns.refuse(id, because: nil) }
        unexplained = []
        guard let id = compaction else { return }
        compaction = nil
        if client.capabilities.compaction { await send(ACPCompaction.cancelled(id)) }
    }

    /// Tells the client one thing a saved session holds (`session/load`). What was said live about a run is not history and is
    /// not replayed (Session Setup, "Loading a session"), and a record holds no question still waiting for its answer.
    mutating func replay(_ update: ConversationUpdate, in turns: ACPTurns) async {
        switch update {
            case .notice, .askApproval, .askQuestions, .askInput: return
            case .runEnded, .returnQueuedPrompts, .promptAccepted, .promptRefused: return
            default: await show(update, in: turns)
        }
    }

    /// Tells the client of a call, a notice or a compaction, asks it an approval, declines what it cannot be asked yet, or sends
    /// what ``ACPUpdate`` maps.
    private mutating func show(_ update: ConversationUpdate, in turns: ACPTurns) async {
        switch update {
            case .toolStarted, .toolFinished, .toolProgress: await call(update)
            case .askApproval(let id, let question, let kind, let detail):
                await approve(id, question, kind, detail, in: turns)
            case .askQuestions(let id, let questions): await ask(id, questions, in: turns)
            // A line a command wants of the person (a key, a code): a form may not ask for a secret, and no command is served
            // yet. Declined, since a turn that waited for it would never end.
            case .askInput(let id, _, _, _): session.conversation.answer(input: id, with: nil)
            case .compacting, .compactionFinished: await compaction(update, in: turns)
            case .notice(let text, let isError):
                // What a command says is its answer, which every client shows; elsewhere it is beside the conversation.
                if answers {
                    await send(ACPCommands.answer(text))
                } else if client.capabilities.notices, let notice = ACPNotice.update(text, isError: isError) {
                    await send(notice)
                }
            default:
                if let payload = ACPUpdate.payload(for: update) { await send(payload) }
        }
    }

    func send(_ update: JSONValue) async {
        await client.notify(["sessionId": .string(session.id), "update": update])
    }
}
