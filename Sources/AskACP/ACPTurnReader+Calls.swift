internal import AemiJSON
internal import AskTUI

/// What a turn asks of the client and tells it of its calls: a tool call's life, a compaction's, an approval, the model's
/// questions.
extension ACPTurnReader {
    /// A tool call: that it began, how far it has got, that it ended. A block with no id is not a call of the model's.
    mutating func call(_ update: ConversationUpdate) async {
        switch update {
            case .toolStarted(let name, let summary, let id?, let fullInput, let command, let path, let rawInput):
                let call = ACPToolCall.Begun(
                    id: id,
                    name: name,
                    summary: summary,
                    fullInput: fullInput,
                    isCommand: command != nil,
                    path: path,
                    rawInput: rawInput
                )
                let started = ACPToolCall.started(call, in: session.folder)
                running.append(Call(id: id, title: started.title, change: started.change))
                await send(started.update)
            case .toolProgress(let id, let text):
                guard let index = running.firstIndex(where: { $0.id == id }) else { return }
                running[index].progressed = true
                await send(ACPToolCall.progressed(id: id, title: running[index].title, progress: text))
            case .toolFinished(let status, let output, let id?, _, _, _):
                // Its progress was on its title: it has its own again.
                let call = running.first { $0.id == id }
                running.removeAll { $0.id == id }
                let title = call?.progressed == true ? call?.title : nil
                await send(ACPToolCall.finished(id: id, status, output: output, title: title, change: call?.change))
            default: break
        }
    }

    /// A compaction, for a client that shows them: begun and ended under one id, or told once when it ends with none begun, as
    /// one a saved session holds does.
    mutating func compaction(_ update: ConversationUpdate, in turns: ACPTurns) async {
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

    /// Asks the person the model's questions, through a client that shows forms, and answers the conversation; a client that
    /// shows none is not asked, and the questions are declined, which the model is told.
    func ask(_ id: Int, _ questions: [ScreenQuestion], in turns: ACPTurns) async {
        guard client.capabilities.form else { return session.conversation.answer(questions: id, with: nil) }
        let request = ACPElicitation.request(session: session.id, call: running.last?.id, questions: questions)
        let answer = await turns.asking { [client] in await client.elicit(request) }
        session.conversation.answer(questions: id, with: ACPElicitation.answers(from: answer, to: questions))
    }

    /// Asks the client the approval the conversation asked as `id`, about the call that began last, and answers the conversation.
    mutating func approve(
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
        let answer = await turns.asking { [client] in await client.requestPermission(request) }
        let choice = ACPPermission.choice(from: answer, kind: kind)
        session.conversation.answer(approval: id, with: choice)
        if running.last?.id == call.id {
            await send(ACPToolCall.resumed(id: call.id, title: call.title, running: choice != .deny))
        } else {
            await send(ACPToolCall.finished(id: call.id, choice == .deny ? .failed("") : .succeeded, output: ""))
        }
    }
}
