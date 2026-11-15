internal import AemiJSON
internal import AskTUI

/// One turn as it is read (ACP v1, Prompt Turn): each thing the conversation says is told to the client before the next is read,
/// so the client sees them in the order they were said, and an approval is asked of it where the screen would ask the person.
struct ACPTurnReader {
    let session: ACPSession
    let client: ACPClient
    /// Why the turn failed, when it did.
    private(set) var failure: String?
    private(set) var failed = false
    /// The calls that began and have not ended, oldest first, with the titles they were given.
    private var running: [(id: String, title: String)] = []

    init(session: ACPSession, client: ACPClient) {
        self.session = session
        self.client = client
    }

    /// Reads one update; false when it ended the turn. `turns` is told what became of a prompt sent during the turn.
    mutating func read(_ update: ConversationUpdate, in turns: ACPTurns) async -> Bool {
        switch update {
            case .runEnded: return false
            case .returnQueuedPrompts: failed = true
            case .notice(let reason, isError: true): failure = reason
            case .promptAccepted(let id, _): turns.take(id)
            case .promptRefused(let id): turns.refuse(id, because: failure)
            default: await show(update)
        }
        return true
    }

    /// Tells the client one thing a saved session holds (`session/load`). What was said live about a run is not history and is
    /// not replayed (Session Setup, "Loading a session"), and a record holds no question still waiting for its answer.
    mutating func replay(_ update: ConversationUpdate) async {
        switch update {
            case .notice, .askApproval, .askQuestions, .askInput: return
            case .runEnded, .returnQueuedPrompts, .promptAccepted, .promptRefused: return
            default: await show(update)
        }
    }

    /// Tells the client of a call, asks it an approval, declines what it cannot be asked yet, or sends what ``ACPUpdate`` maps.
    private mutating func show(_ update: ConversationUpdate) async {
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
                running.append((id, started.title))
                await send(started.update)
            case .toolFinished(let status, let output, let id?, _, _, _):
                running.removeAll { $0.id == id }
                await send(ACPToolCall.finished(id: id, status, output: output))
            case .askApproval(let id, let question, let kind, let detail):
                await approve(id, question, kind, detail)
            // Until the client can be asked these (elicitation), nobody can answer, and a turn that waited would never end.
            case .askQuestions(let id, _): session.conversation.answer(questions: id, with: nil)
            case .askInput(let id, _, _, _): session.conversation.answer(input: id, with: nil)
            default:
                if let payload = ACPUpdate.payload(for: update) { await send(payload) }
        }
    }

    /// Asks the client the approval the conversation asked as `id`, about the call that began last, and answers the conversation.
    private mutating func approve(_ id: Int, _ question: String, _ kind: ApprovalKind, _ detail: String?) async {
        // A question no call of the model's is behind (a command of the person's own) is shown as a call of its own.
        let call = running.last ?? (id: "approval-\(id)", title: question)
        let answer = await client.requestPermission(
            ACPPermission.request(session: session.id, call: call.id, question: question, detail: detail, kind: kind)
        )
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
