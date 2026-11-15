internal import AemiJSON
internal import AskTUI

/// One turn as it is read (ACP v1, Prompt Turn): each thing the conversation says is told to the client before the next is read,
/// so the client sees them in the order they were said, and an approval is asked of it where the screen would ask the person.
struct ACPTurnReader {
    /// A call that began and has not ended: the title it was given, and whether its progress has been said on it.
    private struct Call {
        let id: String
        let title: String
        var progressed = false
    }

    let session: ACPSession
    let client: ACPClient
    private(set) var failed = false
    /// The last error said before something else was, and the one said just now, which may be a refused message's reason.
    private var settled: String?
    private var recent: String?
    /// The messages refused with no reason given yet: a hook's refusal comes before its reason.
    private var unexplained: [Int] = []
    /// The calls that began and have not ended, oldest first.
    private var running: [Call] = []
    /// The compaction that began and has not ended.
    private var compaction: String?

    init(session: ACPSession, client: ACPClient) {
        self.session = session
        self.client = client
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
            // Until the client can be asked these (elicitation), nobody can answer, and a turn that waited would never end.
            case .askQuestions(let id, _): session.conversation.answer(questions: id, with: nil)
            case .askInput(let id, _, _, _): session.conversation.answer(input: id, with: nil)
            case .compacting, .compactionFinished: await compaction(update, in: turns)
            case .notice(let text, let isError):
                if client.capabilities.notices, let notice = ACPNotice.update(text, isError: isError) {
                    await send(notice)
                }
            default:
                if let payload = ACPUpdate.payload(for: update) { await send(payload) }
        }
    }

    /// A tool call: that it began, how far it has got, that it ended. A block with no id is not a call of the model's.
    private mutating func call(_ update: ConversationUpdate) async {
        switch update {
            case .toolStarted(let name, let summary, let id?, let fullInput, let command, let path):
                let call = ACPToolCall.Begun(
                    id: id,
                    name: name,
                    summary: summary,
                    fullInput: fullInput,
                    isCommand: command != nil,
                    path: path
                )
                let started = ACPToolCall.started(call, in: session.folder)
                running.append(Call(id: id, title: started.title))
                await send(started.update)
            case .toolProgress(let id, let text):
                guard let index = running.firstIndex(where: { $0.id == id }) else { return }
                running[index].progressed = true
                await send(ACPToolCall.progressed(id: id, title: running[index].title, progress: text))
            case .toolFinished(let status, let output, let id?, _, _, _):
                // Its progress was on its title: it has its own again.
                let title = running.first { $0.id == id && $0.progressed }?.title
                running.removeAll { $0.id == id }
                await send(ACPToolCall.finished(id: id, status, output: output, title: title))
            default: break
        }
    }

    /// A compaction, for a client that shows them: begun and ended under one id, or told once when it ends with none begun, as
    /// one a saved session holds does.
    private mutating func compaction(_ update: ConversationUpdate, in turns: ACPTurns) async {
        switch update {
            case .compacting(true):
                let id = turns.nextCompactionID()
                compaction = id
                if client.capabilities.compaction { await send(ACPCompaction.began(id)) }
            case .compactionFinished(let status, let text, _):
                let id = compaction ?? turns.nextCompactionID()
                compaction = nil
                if client.capabilities.compaction { await send(ACPCompaction.ended(id, status, text: text)) }
            // That one ended is said by how it ended.
            default: break
        }
    }

    /// Asks the client the approval the conversation asked as `id`, about the call that began last, and answers the conversation.
    private mutating func approve(
        _ id: Int,
        _ question: String,
        _ kind: ApprovalKind,
        _ detail: String?,
        in turns: ACPTurns
    ) async {
        // A question no call of the model's is behind (a command of the person's own) is shown as a call of its own.
        let call = running.last ?? Call(id: "approval-\(id)", title: question)
        let request = ACPPermission.request(
            session: session.id,
            call: call.id,
            question: question,
            detail: detail,
            kind: kind
        )
        // Through the turn, which stops waiting when it is cancelled.
        let answer = await turns.permission(request, from: client)
        let choice = ACPPermission.choice(from: answer, kind: kind)
        session.conversation.answer(approval: id, with: choice)
        if running.last?.id == call.id {
            await send(ACPToolCall.resumed(id: call.id, title: call.title, running: choice != .deny))
        } else {
            await send(ACPToolCall.finished(id: call.id, choice == .deny ? .failed("") : .succeeded, output: ""))
        }
    }

    private func send(_ update: JSONValue) async {
        await client.notify(["sessionId": .string(session.id), "update": update])
    }
}
