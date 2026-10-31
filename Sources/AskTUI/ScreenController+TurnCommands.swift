/// Commands typed while a turn runs (roadmap 0113): beside it when they apply at once, after it when they need its end.
extension ScreenController {
    /// Runs a conversation command: as the screen's run when idle; beside a running turn when it applies at once; after the turn when
    /// it needs the turn's end; else refused while a turn runs.
    mutating func runCommand(_ command: SlashCommand, arguments: String, line: String) -> [Effect] {
        guard state.running else {
            state.transcript.addUser(line)
            return begin(.runCommand(name: command.name, arguments: arguments))
        }
        switch command.duringTurn {
            case .atOnce:
                state.transcript.addUser(line)
                turnCommands.besideRunning += 1
                return [.runCommandBeside(name: command.name, arguments: arguments)]
            case .afterTurn:
                state.transcript.addQueued(line)
                turnCommands.waiting.append(
                    TurnCommands.Waiting(
                        line: line, name: command.name, arguments: arguments,
                        transcriptIndex: state.transcript.items.count - 1))
                return []
            case .refused:
                state.transcript.addUser(line)
                _ = busy()
                return []
        }
    }

    /// Whether the run's end starts a waiting command: there is one, ask is not leaving, and the input is not being given back, unless
    /// the person stopped the turn and queued input is still sent after a stop.
    var startsWaitingCommand: Bool {
        guard !turnCommands.waiting.isEmpty, state.exitRequest == nil else { return false }
        return !returningInput || (interruptedByPerson && options.interruptSendsQueued != .none)
    }

    /// Starts the first waiting command, its line shown as sent.
    mutating func startWaitingCommand() -> [Effect] {
        returningInput = false
        interruptedByPerson = false
        let command = turnCommands.waiting.removeFirst()
        showSent(at: command.transcriptIndex, queued: command.line, as: command.line)
        return begin(.runCommand(name: command.name, arguments: command.arguments))
    }

    /// The waiting commands' lines, taken back for the input, by where they stand in the transcript.
    mutating func takeWaitingCommands() -> [(index: Int, text: String)] {
        defer { turnCommands.waiting.removeAll() }
        return turnCommands.waiting.map { ($0.transcriptIndex, $0.line) }
    }

    /// A question asked while a command runs beside the run belongs to that command.
    mutating func noteQuestion(id: Int) {
        if turnCommands.besideRunning > 0 { turnCommands.besideInputID = id }
    }

    /// Whether the run's end takes the question away: not one a command beside it asked.
    var runOwnsQuestion: Bool { state.pendingInput.map { $0.id != turnCommands.besideInputID } ?? false }

    /// A command beside the run ended: its question goes with it.
    mutating func besideEnded() {
        turnCommands.besideRunning = Swift.max(0, turnCommands.besideRunning - 1)
        if let id = turnCommands.besideInputID, state.pendingInput?.id == id {
            state.pendingInput = nil
            state.inputAnswer.clear()
        }
        if turnCommands.besideRunning == 0 { turnCommands.besideInputID = nil }
    }

    /// The transcript's waiting line at `index` shown as sent, as `text`; added anew when the line there is no longer the waiting one.
    mutating func showSent(at index: Int, queued: String, as text: String) {
        // Still the queued line it was: the spinner moves the revision on every tick, so the item is checked, not the revision.
        guard state.transcript.items.indices.contains(index), state.transcript.items[index] == .queued(queued) else {
            state.transcript.addUser(text)
            return
        }
        state.transcript.items[index] = .user(text)
        state.transcript.progress[index] = nil
        state.transcript.revisions[index] = state.transcript.bump()
    }
}
