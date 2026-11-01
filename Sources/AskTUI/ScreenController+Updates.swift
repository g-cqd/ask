internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

// What each conversation update does to the screen; apart from ScreenController.swift to keep each file
// under the 250-line ceiling and the type body under 200 lines.
extension ScreenController {
    mutating func apply(_ update: ConversationUpdate) -> [Effect] {
        if update.showsTheModelIsBack { modelIsBack() }
        switch update {
            case .batch(let updates): return updates.flatMap { apply($0) }
            case .userPrompt(let text): replayPrompt(text)
            case .assistantText(let text): state.transcript.addAssistantText(text)
            case .thinkingText(let text): state.transcript.addThinkingText(text)
            case .toolStarted, .toolFinished: return applyTool(update)
            case .jobOutput(let job): state.transcript.updateJob(job)
            case .notice(let text, let isError):
                state.transcript.addNotice(HomePath.abbreviate(text, home: options.home), isError: isError)
            case .detail(let text): receive(detail: HomePath.abbreviate(text, home: options.home))
            case .requestExit(let exit): state.exitRequest = exit
            case .label, .labelVariants, .sandboxActive, .sessionIdentity, .status, .context: applyStatusLine(update)
            case .runners(let list): setRunners(list)
            case .runnerOutput: break
            case .files(let list): return receive(files: list)
            case .skills(let list): receive(skills: list)
            case .choices(let command, let rows): return receive(command: command, choices: rows)
            case .configEditor(let snapshot): return receive(config: snapshot)
            case .askInput(let id, let prompt, let secret): askInput(id: id, prompt: prompt, secret: secret)
            case .fillDraft(let text):
                fill(draft: text)
                // A draft that is a command with a list opens it, without waiting for a key.
                return refreshPicker(screenRows: pickerScreenRows, at: .now)
            case .promptAccepted(let id, let text):
                replaceQueuedPrompt(id: id, text: text)
            case .returnQueuedPrompts: returningInput = true
            case .clearConversation: clearConversation()
            case .askApproval(let id, let question, let kind, let detail):
                ask(id: id, question: question, kind: kind, detail: detail)
            case .askQuestions(let id, let questions): askQuestions(id: id, questions: questions)
            case .compacting, .compactionFinished, .reconnecting, .connectingMCP, .waitingForNetwork:
                applyBackgroundWork(update)
            case .runEnded: return runEnded()
            case .besideEnded: besideEnded()
            case .promptRefused(let id): refuseQueuedPrompt(id: id)
        }
        return []
    }

    /// A tool's start or end. Called with those two updates only.
    private mutating func applyTool(_ update: ConversationUpdate) -> [Effect] {
        if case .toolStarted(let name, let summary, let id, let input, let command, let path) = update {
            state.transcript.startTool(
                name: name,
                summary: summary,
                id: id,
                fullInput: input,
                command: command,
                path: path
            )
        } else if case .toolFinished(let status, let output, let id, let job, let replacements) = update {
            state.transcript.finishTool(
                status,
                output: output,
                id: id,
                backgroundJob: job,
                replacements: replacements
            )
            if let job { return [.watchJob(id: job)] }
        }
        return []
    }

    /// What the status line shows: the label, the sandbox, the session's colour, the detail and the context. Called with those
    /// updates only.
    private mutating func applyStatusLine(_ update: ConversationUpdate) {
        switch update {
            case .label(let text):
                state.label = text
                state.labelVariants = []
            case .labelVariants(let forms):
                guard let first = forms.first else { break }
                state.label = first
                state.labelVariants = forms
            case .sandboxActive(let active): state.sandboxed = active
            case .sessionIdentity(let seed): state.sessionIdentity = seed
            case .status(let text): state.detail = text
            case .context(let text): state.context = text
            default: break
        }
    }

    private mutating func clearConversation() {
        state.transcript.removeAll()
        clearSelection()
        state.detail = ""
        state.context = ""
        state.scrollback = 0
    }
}
